// Network poller (kqueue), sockets, deadlines, HTTP.
package main

import (
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

func check(ok bool, what string, args ...any) {
	if !ok {
		fmt.Println("FAIL:", what, args)
		os.Exit(1)
	}
}

func echo(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		go func() { defer c.Close(); io.Copy(c, c) }()
	}
}

func roundTrip(network, addr string) {
	c, err := net.Dial(network, addr)
	check(err == nil, "dial "+network, err)
	defer c.Close()
	msg := []byte("hello over " + network)
	_, err = c.Write(msg)
	check(err == nil, "write", err)
	buf := make([]byte, len(msg))
	_, err = io.ReadFull(c, buf)
	check(err == nil && string(buf) == string(msg), "echo "+network, err)

	// nothing more to read: the deadline must fire through the poller
	c.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
	_, err = c.Read(buf)
	var ne net.Error
	check(errors.As(err, &ne) && ne.Timeout(), "read deadline", err)
}

func main() {
	tl, err := net.Listen("tcp", "127.0.0.1:0")
	check(err == nil, "listen tcp", err)
	go echo(tl)
	roundTrip("tcp", tl.Addr().String())
	check(tl.Addr().(*net.TCPAddr).Port != 0, "tcp local port")

	dir, err := os.MkdirTemp("", "bitten-net")
	check(err == nil, "tempdir", err)
	defer os.RemoveAll(dir)
	sock := filepath.Join(dir, "s.sock")
	ul, err := net.Listen("unix", sock)
	check(err == nil, "listen unix", err)
	go echo(ul)
	roundTrip("unix", sock)

	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	check(err == nil, "listen udp", err)
	uc, err := net.Dial("udp", pc.LocalAddr().String())
	check(err == nil, "dial udp", err)
	uc.Write([]byte("ping"))
	buf := make([]byte, 16)
	pc.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, from, err := pc.ReadFrom(buf)
	check(err == nil && string(buf[:n]) == "ping" && from != nil, "udp", err)

	_, err = net.DialTimeout("tcp", "127.0.0.1:1", time.Second)
	check(err != nil, "connect to a closed port fails")

	hl, err := net.Listen("tcp", "127.0.0.1:0")
	check(err == nil, "listen http", err)
	go http.Serve(hl, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "path=%s", r.URL.Path)
	}))
	resp, err := http.Get("http://" + hl.Addr().String() + "/bitten")
	check(err == nil, "http get", err)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	check(string(body) == "path=/bitten", "http body", string(body))

	addrs, err := net.LookupHost("localhost")
	check(err == nil && len(addrs) > 0, "lookup localhost", err)
	fmt.Println("go netio ok")
}
