package chord

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"time"

	log "github.com/sirupsen/logrus"
)

// runnerResult mirrors the JSON contract printed by netmiko-runner.py:
// {"ok": bool, "output": string|null, "error": string|null, "error_type": string|null}
type runnerResult struct {
	Ok        bool    `json:"ok"`
	Output    *string `json:"output"`
	Error     *string `json:"error"`
	ErrorType *string `json:"error_type"`
}

/*
 * Function:	runCommand
 *
 * Description:
 *		Shell out to the network-automation script to run a read-only command
 * 		against the device at host. Credentials are never passed on the command
 * 		line or through the ring - the script falls back to NETMIKO_USER/
 * 		NETMIKO_PASS/NETMIKO_SECRET/NETMIKO_PORT env vars set locally on this
 * 		node's container.
 */
func (n *Node) runCommand(host string, command string) ([]byte, error) {
	timeout := time.Duration(n.config.AutomationTimeout)*time.Second + 5*time.Second
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, n.config.AutomationInterpreter, n.config.AutomationScript,
		"--host", host,
		"--command", command,
		"--timeout", strconv.Itoa(n.config.AutomationTimeout),
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	runErr := cmd.Run()
	if stderr.Len() > 0 {
		log.Infof("runCommand(%s): automation script stderr:\n%s", host, stderr.String())
	}

	var result runnerResult
	if err := json.Unmarshal(bytes.TrimSpace(stdout.Bytes()), &result); err != nil {
		if runErr != nil {
			return nil, fmt.Errorf("automation script failed and produced no valid JSON output: %w", runErr)
		}
		return nil, fmt.Errorf("failed to parse automation script output as JSON: %w", err)
	}

	if !result.Ok {
		errType := "unknown"
		if result.ErrorType != nil {
			errType = *result.ErrorType
		}
		errMsg := "no error message provided"
		if result.Error != nil {
			errMsg = *result.Error
		}
		return nil, fmt.Errorf("automation command failed [%s]: %s", errType, errMsg)
	}

	if result.Output == nil {
		return nil, errors.New("automation script reported ok=true but returned no output")
	}

	return []byte(*result.Output), nil
}

/*
 * Function:	run
 *
 * Description:
 *		Run a command against the device identified by host. Locate which node
 * 		in the ring is responsible for host, then execute locally or forward
 * 		via RunRPC. The result is cached in the same replicated datastore used
 * 		by put/get under key=host, so a replica still has the last known output
 * 		if the owning node fails.
 *
 * 		Known limitation: this shares the KV keyspace with regular put/get, so
 * 		a put() using a key equal to a device host would collide with a cached
 * 		Run result. Acceptable for this project's scope.
 */
func (n *Node) run(host string, command string) ([]byte, error) {
	node, err := n.locate(host)
	if err != nil {
		return nil, err
	}

	if bytes.Compare(n.Id, node.Id) == 0 {
		// device key belongs to current node
		output, err := n.runCommand(host, command)
		if err != nil {
			log.Errorf("error running automation command for host %s: %s", host, err)
			return nil, err
		}

		// cache the result and replicate it, same as put()
		myId := BytesToUint64(n.Id)
		n.rgsMtx.RLock()
		n.rgs[myId].data[host] = output
		n.rgsMtx.RUnlock()
		n.sendReplica(host)

		return output, nil
	} else {
		// device key belongs to remote node
		val, err := n.RunRPC(node, host, command)
		if err != nil {
			log.Errorf("error running automation command on a remote node: %s", err)
			return nil, err
		}
		return val.Value, nil
	}
}
