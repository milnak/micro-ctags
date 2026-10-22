package ctags_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestWindowsFzfDefaultCommand(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("requires Windows CMD and a console")
	}
	console, err := os.Open("CONIN$")
	if err != nil {
		t.Skipf("requires an attached console: %v", err)
	}
	defer console.Close()
	executable := os.Getenv("FZF_TEST_EXECUTABLE")
	if executable == "" {
		executable, err = exec.LookPath("fzf")
		if err != nil {
			t.Skipf("fzf is not installed: %v", err)
		}
	}
	filename := filepath.Join(t.TempDir(), "tags with spaces & %percent% !bang!.txt")
	if err := os.WriteFile(filename, []byte("7\tfunction\tExample::target(first, second)\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("SHELL", "cmd.exe")
	t.Setenv("MICRO_CTAGS_INPUT", filename)
	t.Setenv("FZF_DEFAULT_COMMAND", `type "%MICRO_CTAGS_INPUT%"`)
	t.Setenv("FZF_DEFAULT_OPTS", "")
	t.Setenv("FZF_DEFAULT_OPTS_FILE", "")
	for _, shell := range []string{"cmd.exe /d /v:off /s /c", ""} {
		command := exec.Command(executable, "--with-shell="+shell,
			"--filter=target", "--with-nth=3..", "--accept-nth=1", "--delimiter=\t")
		command.Stdin = console
		output, err := command.CombinedOutput()
		if shell != "" {
			t.Logf("explicit-shell baseline: error=%v, output=%q", err, output)
			continue
		}
		if err != nil {
			t.Fatalf("default CMD reader failed: %v; output=%q", err, output)
		}
		if strings.TrimSpace(string(output)) != "7" {
			t.Fatalf("expected selected line 7, got %q", output)
		}
	}
}
