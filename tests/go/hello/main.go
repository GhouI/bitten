// Runtime basics: scheduler, timers, GC, signal-based preemption.
package main

import (
	"fmt"
	"os"
	"runtime"
	"sync"
	"sync/atomic"
	"time"
)

func check(ok bool, what string) {
	if !ok {
		fmt.Println("FAIL:", what)
		os.Exit(1)
	}
}

func main() {
	check(runtime.GOOS == "darwin", "GOOS is darwin")
	check(runtime.NumCPU() >= 1, "NumCPU")
	check(len(os.Args) >= 1, "args")
	exe, err := os.Executable()
	check(err == nil && exe != "", "os.Executable")

	var wg sync.WaitGroup
	var sum atomic.Int64
	ch := make(chan int, 16)
	for i := 0; i < 64; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			time.Sleep(time.Duration(i%5) * time.Millisecond)
			sum.Add(int64(i))
			ch <- i
		}(i)
	}
	go func() { wg.Wait(); close(ch) }()
	n := 0
	for range ch {
		n++
	}
	check(n == 64 && sum.Load() == 2016, "goroutines and channels")

	// A goroutine that never yields: the collector can only stop it with
	// an asynchronous preemption signal that rewrites its registers.
	var spin atomic.Bool
	spin.Store(true)
	var x uint64
	go func() {
		for spin.Load() {
			x++
		}
	}()
	garbage := make([][]byte, 0, 256)
	for i := 0; i < 256; i++ {
		garbage = append(garbage, make([]byte, 1<<16))
	}
	start := time.Now()
	for i := 0; i < 5; i++ {
		runtime.GC()
	}
	spin.Store(false)
	check(time.Since(start) < 20*time.Second, "GC with a spinning goroutine")
	check(len(garbage) == 256, "allocations")

	t := time.NewTimer(30 * time.Millisecond)
	t0 := time.Now()
	<-t.C
	d := time.Since(t0)
	check(d >= 25*time.Millisecond && d < 2*time.Second, "timer accuracy")

	host, err := os.Hostname()
	check(err == nil && host != "", "hostname")
	fmt.Println("go hello ok:", runtime.Version(), runtime.GOOS+"/"+runtime.GOARCH)
}
