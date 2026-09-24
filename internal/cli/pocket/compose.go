package pocket

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func composeCmd(dir string) (bin string, prefix []string) {
	composeFile := "docker-compose.yaml"
	if _, err := os.Stat(filepath.Join(dir, composeFile)); err != nil {
		if _, err2 := os.Stat(filepath.Join(dir, "docker-compose.yml")); err2 == nil {
			composeFile = "docker-compose.yml"
		}
	}
	args := []string{"compose", "-f", composeFile}
	if _, err := exec.LookPath("docker"); err == nil {
		return "docker", args
	}
	if _, err := exec.LookPath("podman"); err == nil {
		return "podman", args
	}
	return "docker", args
}

func composeRun(ctx context.Context, dir string, args ...string) error {
	bin, prefix := composeCmd(dir)
	cmdArgs := append(append([]string{}, prefix...), args...)
	cmd := exec.CommandContext(ctx, bin, cmdArgs...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s %s: %w", bin, strings.Join(cmdArgs, " "), err)
	}
	return nil
}

func stopPocketID(ctx context.Context, dir string) error {
	return composeRun(ctx, dir, "stop", "pocket-id")
}

func startPocketID(ctx context.Context, dir string) error {
	return composeRun(ctx, dir, "up", "-d", "pocket-id")
}
