#!/usr/bin/env python3
"""
mock-runner.py — sustituto de netmiko-runner.py para los experimentos SIN hardware.

Respeta el MISMO contrato de stdout que netmiko-runner.py: imprime exactamente una
linea de JSON {"ok","output","error","error_type"} y nada mas en stdout; todo lo
demas va a stderr. Exit 0 si ok, 1 si no. No abre ninguna conexion de red: simula la
salida de un comando "show" para poder demostrar el enrutamiento + cache + replicacion
del resultado de `run` en el anillo Chord sin necesitar un router real.

El nodo Go lo invoca igual que al runner real:
    <interprete> mock-runner.py --host <h> --command <cmd> --timeout <n>
"""
import argparse
import json
import sys


def eprint(msg):
    print(msg, file=sys.stderr)
    sys.stderr.flush()


def main():
    parser = argparse.ArgumentParser(description="Runner simulado (sin red) para experimentos.")
    parser.add_argument("--host", required=False)
    parser.add_argument("--command", required=False)
    parser.add_argument("--timeout", type=int, default=20)
    # aceptados por compatibilidad con el runner real; ignorados aqui
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--username", default=None)
    parser.add_argument("--password", default=None)
    parser.add_argument("--secret", default="")
    parser.add_argument("--device-type", default="cisco_ios")
    args = parser.parse_args()

    if not args.host:
        result = {"ok": False, "output": None,
                  "error": "Falta --host", "error_type": "config"}
        print(json.dumps(result))
        sys.exit(1)

    eprint(f"[mock] simulando '{args.command}' contra {args.host} (sin red)")
    fake_output = (
        f"[MOCK {args.host}] {args.command}\n"
        "Interface              IP-Address      OK? Method Status                Protocol\n"
        "GigabitEthernet1       10.0.0.1        YES manual up                    up\n"
        "GigabitEthernet2       unassigned      YES unset  administratively down down"
    )
    result = {"ok": True, "output": fake_output, "error": None, "error_type": None}
    print(json.dumps(result))
    sys.exit(0)


if __name__ == "__main__":
    main()
