// Processes, signals and the file system through the Go standard library.
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func check(ok bool, what string, args ...any) {
	if !ok {
		fmt.Println("FAIL:", what, args)
		os.Exit(1)
	}
}

func main() {
	// A Mach-O parent spawning an ordinary Linux program.
	cmd := exec.Command("/bin/sh", "-c", "echo out; echo err >&2; exit 3")
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	ee, ok := err.(*exec.ExitError)
	check(ok && ee.ExitCode() == 3, "exit status", err)
	check(stdout.String() == "out\n" && stderr.String() == "err\n", "pipes", stdout.String(), stderr.String())

	// Re-executing ourselves: Mach-O spawning Mach-O through the loader.
	if len(os.Args) > 1 && os.Args[1] == "child" {
		fmt.Print("child:" + os.Getenv("BITTEN_TEST"))
		os.Exit(7)
	}
	self, err := os.Executable()
	check(err == nil, "executable", err)
	c2 := exec.Command(self, "child")
	c2.Env = append(os.Environ(), "BITTEN_TEST=42")
	out, err := c2.Output()
	ee, ok = err.(*exec.ExitError)
	check(ok && ee.ExitCode() == 7 && string(out) == "child:42", "re-exec", err, string(out))

	// Killing a child with a signal reports Darwin's signal number.
	c3 := exec.Command("/bin/sh", "-c", "sleep 30")
	check(c3.Start() == nil, "start sleep")
	time.Sleep(50 * time.Millisecond)
	c3.Process.Signal(syscall.SIGUSR1)
	err = c3.Wait()
	ee, ok = err.(*exec.ExitError)
	ws, _ := ee.Sys().(syscall.WaitStatus)
	check(ok && ws.Signaled() && ws.Signal() == syscall.SIGUSR1, "signal death", err)

	// Signals delivered to ourselves.
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGUSR2, syscall.SIGWINCH)
	syscall.Kill(os.Getpid(), syscall.SIGUSR2)
	select {
	case s := <-sigs:
		check(s == syscall.SIGUSR2, "signal number", s)
	case <-time.After(5 * time.Second):
		check(false, "signal delivery timed out")
	}

	// Files and directories.
	dir, err := os.MkdirTemp("", "bitten-fs")
	check(err == nil, "tempdir", err)
	defer os.RemoveAll(dir)
	for _, n := range []string{"b.txt", "a.txt", "c.txt"} {
		check(os.WriteFile(filepath.Join(dir, n), []byte(n), 0o640) == nil, "write "+n)
	}
	check(os.Symlink("a.txt", filepath.Join(dir, "link")) == nil, "symlink")
	ents, err := os.ReadDir(dir)
	check(err == nil && len(ents) == 4, "readdir", err, len(ents))
	names := []string{}
	for _, e := range ents {
		names = append(names, e.Name())
	}
	check(strings.Join(names, ",") == "a.txt,b.txt,c.txt,link", "sorted names", names)
	st, err := os.Stat(filepath.Join(dir, "link"))
	check(err == nil && st.Size() == 5 && st.Mode().Perm() == 0o640, "stat", err)
	lst, err := os.Lstat(filepath.Join(dir, "link"))
	check(err == nil && lst.Mode()&os.ModeSymlink != 0, "lstat", err)
	check(os.Rename(filepath.Join(dir, "a.txt"), filepath.Join(dir, "z.txt")) == nil, "rename")
	_, err = os.Stat(filepath.Join(dir, "a.txt"))
	check(os.IsNotExist(err), "ENOENT maps to ErrNotExist", err)
	wd, err := os.Getwd()
	check(err == nil && wd != "", "getwd", err)
	fmt.Println("go procs ok")
}
