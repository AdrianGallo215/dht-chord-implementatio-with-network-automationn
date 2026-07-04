import argparse
import json
import os
import socket
import sys
import time
import traceback
import threading

try:
    from netmiko import ConnectHandler
    from netmiko.exceptions import (
        NetmikoTimeoutException,
        NetmikoAuthenticationException,
    )
except ImportError:
    sys.stderr.write(
        "[FATAL] No se encontró el paquete 'netmiko'. "
        "Instálalo con: pip install netmiko\n"
        "Si esto ocurre dentro de Docker, revisa el Dockerfile: "
        "probablemente falló 'pip install' por falta de internet en el build.\n"
    )
    sys.exit(2)

try:
    import paramiko
    from paramiko.ssh_exception import SSHException
except ImportError:
    paramiko = None
    SSHException = Exception  # fallback para que el except no rompa


DISABLED_ALGORITHMS_WORKAROUND = {
    # Descomenta si ves errores de "key exchange algorithm not found":
    # "disabled_algorithms": {"pubkeys": ["rsa-sha2-256", "rsa-sha2-512"]}
}


def eprint(msg):
    """Imprime diagnóstico a stderr, nunca a stdout (stdout es solo para el JSON final)."""
    sys.stderr.write(f"[diag] {msg}\n")
    sys.stderr.flush()


def check_tcp_reachability(host, port=22, timeout=5):
    """
    Preflight: intenta abrir un socket TCP crudo antes de meter a Netmiko
    en la ecuación. Esto separa 'problema de red' de 'problema de SSH/auth'.
    """
    try:
        with socket.create_connection((host, port), timeout=timeout):
            eprint(f"OK: puerto {port} de {host} responde a nivel TCP.")
            return True, None
    except socket.timeout:
        return False, (
            f"Timeout conectando a {host}:{port}. Probable causa: el CR1000v "
            f"no terminó de arrancar, la IP es incorrecta, o falta el "
            f"Adaptador 2 host-only en la DEVASC VM. Ver punto (1) del mapa de errores."
        )
    except ConnectionRefusedError:
        return False, (
            f"Conexión rechazada por {host}:{port}. El host responde pero SSH "
            f"no está escuchando. Revisa 'line vty' y llaves RSA en el CR1000v. "
            f"Ver punto (4) del mapa de errores."
        )
    except socket.gaierror:
        return False, (
            f"No se pudo resolver '{host}'. Usa la IP directa, no un hostname. "
            f"Ver punto (5) del mapa de errores."
        )
    except OSError as e:
        return False, f"Error de red no clasificado: {e}"


def check_memory(min_free_mb=200):
    """
    Preflight: lee /proc/meminfo (Linux) y avisa si hay poca RAM libre.
    No es bloqueante -- solo advierte, porque 'disponible' no siempre es exacto.
    """
    try:
        with open("/proc/meminfo") as f:
            meminfo = f.read()
        available_kb = None
        for line in meminfo.splitlines():
            if line.startswith("MemAvailable:"):
                available_kb = int(line.split()[1])
                break
        if available_kb is not None:
            available_mb = available_kb / 1024
            if available_mb < min_free_mb:
                eprint(
                    f"ADVERTENCIA: solo {available_mb:.0f}MB de RAM disponible "
                    f"(umbral {min_free_mb}MB). Ver punto (7) del mapa de errores: "
                    f"revisa 'free -h' y considera subir la RAM de la VM."
                )
            else:
                eprint(f"OK: {available_mb:.0f}MB de RAM disponible.")
    except FileNotFoundError:
        # No es Linux, o no existe /proc/meminfo (ej. corriendo fuera de la VM).
        eprint("No se pudo leer /proc/meminfo (¿no estás en Linux?), se omite chequeo de RAM.")
    except Exception as e:
        eprint(f"No se pudo chequear memoria: {e}")


def check_thread_limit():
    """
    Preflight: revisa el límite de procesos/hilos del usuario (ulimit -u).
    Este es el error que sueles tener tú en DEVASC.
    """
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NPROC)
        eprint(f"Límite de hilos/procesos (ulimit -u): soft={soft}, hard={hard}")
        if soft != resource.RLIM_INFINITY and soft < 256:
            eprint(
                f"ADVERTENCIA: ulimit -u = {soft} es bajo. Si ves "
                f"'can't start new thread' más abajo, sube el límite con "
                f"'ulimit -u 4096' antes de correr este script, o define "
                f"'ulimits: nproc:' en docker-compose.yml. Ver punto (6)."
            )
    except (ImportError, ValueError):
        # 'resource' no existe en Windows -- no aplica en este entorno (VM Linux).
        pass


def check_internet_dns():
    """
    Preflight opcional: solo relevante si vas a usar hostname en vez de IP,
    o para diagnosticar problemas de pip install (punto 8). No es
    obligatorio para conectar al CR1000v vía IP directa.
    """
    try:
        socket.gethostbyname("pypi.org")
        eprint("OK: la VM tiene resolución DNS / salida a internet (Adaptador NAT funcionando).")
    except socket.gaierror:
        eprint(
            "Sin salida a internet / DNS. Esto es normal si solo estás usando "
            "el Adaptador 2 (host-only) para hablar con el CR1000v -- el "
            "Adaptador 1 (NAT) es el que da internet. Ver punto (8) si esto "
            "afecta un 'pip install'."
        )


def run_preflight_checks(host, port):
    eprint("=== Preflight checks ===")
    check_memory()
    check_thread_limit()
    check_internet_dns()
    reachable, reason = check_tcp_reachability(host, port)
    eprint("=== Fin preflight ===")
    return reachable, reason


def build_result(ok, output=None, error=None, error_type=None):
    return {"ok": ok, "output": output, "error": error, "error_type": error_type}


def execute_command(host, port, username, password, secret, command, device_type, timeout):
    device = {
        "device_type": device_type,
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "secret": secret or "",
        "timeout": timeout,
        "banner_timeout": timeout,
        "auth_timeout": timeout,
        **DISABLED_ALGORITHMS_WORKAROUND,
    }

    net_connect = None
    try:
        net_connect = ConnectHandler(**device)
        if secret:
            net_connect.enable()
        output = net_connect.send_command(command, read_timeout=timeout)
        return build_result(True, output=output)

    except NetmikoTimeoutException as e:
        return build_result(
            False,
            error=f"Timeout de conexión: {e}. Ver punto (1) del mapa de errores en la cabecera del script.",
            error_type="timeout",
        )
    except NetmikoAuthenticationException as e:
        return build_result(
            False,
            error=f"Fallo de autenticación: {e}. Ver punto (2) del mapa de errores.",
            error_type="auth",
        )
    except SSHException as e:
        return build_result(
            False,
            error=f"Error de protocolo SSH: {e}. Probable incompatibilidad de "
                  f"algoritmos legacy del IOS. Ver punto (3) del mapa de errores.",
            error_type="ssh_protocol",
        )
    except ConnectionRefusedError as e:
        return build_result(
            False,
            error=f"Conexión rechazada: {e}. Ver punto (4) del mapa de errores.",
            error_type="connection_refused",
        )
    except socket.gaierror as e:
        return build_result(
            False,
            error=f"No se pudo resolver el host: {e}. Ver punto (5) del mapa de errores.",
            error_type="dns",
        )
    except (RuntimeError, threading.ThreadError) as e:
        return build_result(
            False,
            error=f"Error de hilos/procesos del sistema: {e}. Ver punto (6) del "
                  f"mapa de errores (ulimit -u / hilos zombie).",
            error_type="thread_limit",
        )
    except MemoryError as e:
        return build_result(
            False,
            error=f"Memoria insuficiente en la VM: {e}. Ver punto (7) del mapa de errores.",
            error_type="memory",
        )
    except Exception as e:
        # Fallback genérico -- no debe pasar seguido si los casos de arriba
        # están bien mapeados, pero nunca dejamos que el script muera sin JSON.
        tb = traceback.format_exc(limit=3)
        eprint(f"Excepción no clasificada, traceback:\n{tb}")
        return build_result(
            False,
            error=f"Error no clasificado: {type(e).__name__}: {e}",
            error_type="unknown",
        )
    finally:
        # CRÍTICO para el punto (6): siempre cerrar la sesión para no dejar
        # hilos de Paramiko colgados que agoten el ulimit en corridas futuras.
        if net_connect is not None:
            try:
                net_connect.disconnect()
            except Exception:
                pass


def threading_error_types():
    """threading.ThreadError no siempre existe importado globalmente; lo resolvemos así."""
    import threading
    return (threading.ThreadError,)


def main():
    parser = argparse.ArgumentParser(description="Ejecuta un comando de red vía Netmiko y devuelve JSON.")
    parser.add_argument("--host", default=os.environ.get("NETMIKO_HOST"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("NETMIKO_PORT", "22")))
    parser.add_argument("--username", default=os.environ.get("NETMIKO_USER"))
    parser.add_argument("--password", default=os.environ.get("NETMIKO_PASS"))
    parser.add_argument("--secret", default=os.environ.get("NETMIKO_SECRET", ""))
    parser.add_argument("--command", required=False, help="Comando a ejecutar en el dispositivo")
    parser.add_argument("--device-type", default="cisco_ios")
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--dry-run", action="store_true",
                         help="No conecta a nada; devuelve una salida falsa para validar el contrato JSON con Ivett.")
    parser.add_argument("--selftest", action="store_true",
                         help="Solo corre los preflight checks (memoria, hilos, red) y termina, sin ejecutar comando.")
    args = parser.parse_args()

    if args.dry_run:
        result = build_result(True, output=f"[DRY-RUN] simulación de: {args.command}")
        print(json.dumps(result))
        sys.exit(0)

    if not args.host:
        result = build_result(False, error="Falta --host (o variable de entorno NETMIKO_HOST).", error_type="config")
        print(json.dumps(result))
        sys.exit(1)

    reachable, reason = run_preflight_checks(args.host, args.port)

    if args.selftest:
        result = build_result(reachable, output="Preflight OK" if reachable else None,
                               error=None if reachable else reason,
                               error_type=None if reachable else "preflight")
        print(json.dumps(result))
        sys.exit(0 if reachable else 1)

    if not reachable:
        # No tiene sentido intentar Netmiko si ni siquiera hay TCP -- ahorra
        # tiempo de espera del timeout largo de Netmiko.
        result = build_result(False, error=reason, error_type="preflight")
        print(json.dumps(result))
        sys.exit(1)

    if not args.command:
        result = build_result(False, error="Falta --command a ejecutar.", error_type="config")
        print(json.dumps(result))
        sys.exit(1)

    if not args.username or args.password is None:
        result = build_result(
            False,
            error="Faltan credenciales (--username/--password o NETMIKO_USER/NETMIKO_PASS).",
            error_type="config",
        )
        print(json.dumps(result))
        sys.exit(1)

    result = execute_command(
        host=args.host,
        port=args.port,
        username=args.username,
        password=args.password,
        secret=args.secret,
        command=args.command,
        device_type=args.device_type,
        timeout=args.timeout,
    )
    print(json.dumps(result))
    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
