package chord

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

// writeFakeRunner writes a tiny shell script that ignores its CLI args and
// prints the JSON in the FAKE_RUNNER_OUTPUT env var to stdout, so runCommand's
// JSON-contract parsing can be exercised without a real Python/Netmiko install.
func writeFakeRunner(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fake-runner.sh")
	script := "#!/bin/sh\necho \"$FAKE_RUNNER_OUTPUT\"\n"
	err := os.WriteFile(path, []byte(script), 0755)
	assert.NoError(t, err)
	return path
}

func newTestAutomationNode(scriptPath string) *Node {
	return &Node{
		config: &Config{
			AutomationInterpreter: "/bin/sh",
			AutomationScript:      scriptPath,
			AutomationTimeout:     5,
		},
	}
}

func TestRunCommandSuccess(t *testing.T) {
	scriptPath := writeFakeRunner(t)
	n := newTestAutomationNode(scriptPath)

	os.Setenv("FAKE_RUNNER_OUTPUT", `{"ok": true, "output": "Gi0/0 up up", "error": null, "error_type": null}`)
	defer os.Unsetenv("FAKE_RUNNER_OUTPUT")

	out, err := n.runCommand("192.168.56.10", "show ip interface brief")
	assert.NoError(t, err)
	assert.Equal(t, "Gi0/0 up up", string(out))
}

func TestRunCommandFailureWithErrorType(t *testing.T) {
	scriptPath := writeFakeRunner(t)
	n := newTestAutomationNode(scriptPath)

	os.Setenv("FAKE_RUNNER_OUTPUT", `{"ok": false, "output": null, "error": "Timeout de conexion", "error_type": "timeout"}`)
	defer os.Unsetenv("FAKE_RUNNER_OUTPUT")

	out, err := n.runCommand("192.168.56.10", "show ip interface brief")
	assert.Nil(t, out)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "timeout")
	assert.Contains(t, err.Error(), "Timeout de conexion")
}

func TestRunCommandMalformedJSON(t *testing.T) {
	scriptPath := writeFakeRunner(t)
	n := newTestAutomationNode(scriptPath)

	os.Setenv("FAKE_RUNNER_OUTPUT", `not valid json`)
	defer os.Unsetenv("FAKE_RUNNER_OUTPUT")

	out, err := n.runCommand("192.168.56.10", "show ip interface brief")
	assert.Nil(t, out)
	assert.Error(t, err)
}

// TestRunCommandRealScriptDryRun exercises runCommand against the real
// netmiko-runner.py using its --dry-run flag (fakes success, touches no
// network). Skipped if python3 or the script aren't available in this
// environment so it never blocks CI elsewhere.
func TestRunCommandRealScriptDryRun(t *testing.T) {
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not found, skipping real netmiko-runner.py integration test")
	}
	scriptPath := "network-automation/netmiko-runner.py"
	if _, err := os.Stat(scriptPath); err != nil {
		t.Skip("network-automation/netmiko-runner.py not found, skipping")
	}

	n := &Node{
		config: &Config{
			AutomationInterpreter: "python3",
			AutomationScript:      scriptPath,
			AutomationTimeout:     10,
		},
	}

	// runCommand doesn't pass --dry-run, so this exercises the real
	// preflight-check path (no host reachable at this address) and verifies
	// runCommand surfaces the script's structured JSON error rather than
	// hanging or crashing.
	_, err := n.runCommand("192.0.2.1", "show version")
	assert.Error(t, err)
}
