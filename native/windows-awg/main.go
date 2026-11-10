//go:build windows

// FoxWay's short-lived controller and protected SCM service wrapper.
// The actual protocol, route, DNS and firewall handling is upstream AmneziaWG.
package main

import (
	"app.foxway/windows-awg/guard"
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel/winipcfg"
	"io"
	"log"
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unsafe"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
	"github.com/amnezia-vpn/amneziawg-windows/v3/services"
	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

func ownerName() (string, error) {
	u, e := user.Current()
	if e != nil {
		return "", e
	}
	sum := sha256.Sum256([]byte(u.Uid))
	return fmt.Sprintf("FoxWay-%x", sum[:4]), nil
}
func base() (string, error) {
	root, e := windows.KnownFolderPath(windows.FOLDERID_ProgramFiles, 0)
	if e != nil {
		return "", e
	}
	exe, e := os.Executable()
	if e != nil {
		return "", e
	}
	data, e := os.ReadFile(exe)
	if e != nil {
		return "", e
	}
	sum := sha256.Sum256(data)
	return filepath.Join(root, "FoxWayNative", fmt.Sprintf("%x", sum[:8])), nil
}
func protectedDir(path string) error {
	sd, e := windows.SecurityDescriptorFromString("D:P(A;;FA;;;SY)(A;;FA;;;BA)")
	if e != nil {
		return e
	}
	sa := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: sd}
	parts := []string{filepath.Dir(path), path}
	for _, p := range parts {
		name, e := windows.UTF16PtrFromString(p)
		if e != nil {
			return e
		}
		e = windows.CreateDirectory(name, &sa)
		if e != nil && e != windows.ERROR_ALREADY_EXISTS {
			return e
		}
		attrs, e := windows.GetFileAttributes(name)
		if e != nil {
			return e
		}
		if attrs&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			return errors.New("reparse directory rejected")
		}
	}
	return nil
}
func encrypt(raw []byte, name string) ([]byte, error) {
	if len(raw) == 0 {
		return nil, errors.New("empty")
	}
	in := windows.DataBlob{Size: uint32(len(raw)), Data: &raw[0]}
	out := windows.DataBlob{}
	desc, e := windows.UTF16PtrFromString(name)
	if e != nil {
		return nil, e
	}
	e = windows.CryptProtectData(&in, desc, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN|windows.CRYPTPROTECT_LOCAL_MACHINE, &out)
	if e != nil {
		return nil, e
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	return append([]byte{}, unsafe.Slice(out.Data, int(out.Size))...), nil
}
func stop(name string) error {
	m, e := mgr.Connect()
	if e != nil {
		return e
	}
	defer m.Disconnect()
	serviceName, _ := services.ServiceNameOfTunnel(name)
	s, e := m.OpenService(serviceName)
	if e == windows.ERROR_SERVICE_DOES_NOT_EXIST {
		return nil
	}
	if e != nil {
		return e
	}
	defer s.Close()
	_, _ = s.Control(svc.Stop)
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		state, e := s.Query()
		if e != nil || state.State == svc.Stopped {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	state, e := s.Query()
	if e == nil && state.State != svc.Stopped {
		return errors.New("service did not stop")
	}
	return s.Delete()
}
func writeBinary(path string, data []byte) error {
	old, e := os.ReadFile(path)
	if e == nil && bytes.Equal(old, data) {
		return nil
	}
	return os.WriteFile(path, data, 0600)
}
func up(name, folder string) error {
	raw, e := io.ReadAll(io.LimitReader(os.Stdin, 1048577))
	if e != nil || len(raw) > 1048576 {
		return errors.New("invalid input")
	}
	if regexp.MustCompile(`(?im)^\s*(PreUp|PostUp|PreDown|PostDown|IncludedApplications|ExcludedApplications|SaveConfig)\s*=`).Match(raw) {
		return errors.New("hooks forbidden")
	}
	cfg, e := conf.FromWgQuick(string(raw), name)
	if e != nil {
		return errors.New("invalid config")
	}
	if cfg.Interface.PreUp != "" || cfg.Interface.PostUp != "" || cfg.Interface.PreDown != "" || cfg.Interface.PostDown != "" {
		return errors.New("hooks forbidden")
	}
	if e = protectedDir(folder); e != nil {
		return e
	}
	if e = stop(name); e != nil {
		return e
	}
	source, e := os.Executable()
	if e != nil {
		return e
	}
	exe := filepath.Join(folder, "foxway-awg.exe")
	if !strings.EqualFold(source, exe) {
		bytes, e := os.ReadFile(source)
		if e != nil {
			return e
		}
		if e = writeBinary(exe, bytes); e != nil {
			return e
		}
	}
	dll, e := os.ReadFile(filepath.Join(filepath.Dir(source), "wintun.dll"))
	if e != nil {
		return e
	}
	if e = writeBinary(filepath.Join(folder, "wintun.dll"), dll); e != nil {
		return e
	}
	ciphertext, e := encrypt(raw, name)
	if e != nil {
		return e
	}
	path := filepath.Join(folder, name+".conf.dpapi")
	if e = os.WriteFile(path, ciphertext, 0600); e != nil {
		return e
	}
	m, e := mgr.Connect()
	if e != nil {
		return e
	}
	defer m.Disconnect()
	serviceName, _ := services.ServiceNameOfTunnel(name)
	// Deletion can be asynchronous while the old SCM handle closes.
	var s *mgr.Service
	for i := 0; i < 50; i++ {
		s, e = m.CreateService(serviceName, exe, mgr.Config{StartType: mgr.StartManual, DisplayName: "FoxWay VPN", Dependencies: []string{"Nsi", "TcpIp"}, SidType: windows.SERVICE_SID_TYPE_UNRESTRICTED}, "service", path)
		if e != windows.ERROR_SERVICE_MARKED_FOR_DELETE {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if e != nil {
		return e
	}
	defer s.Close()
	return s.Start()
}
func stats(name string) map[string]any {
	result := map[string]any{"up": false, "rx": uint64(0), "tx": uint64(0)}
	pipe, _ := services.PipePathOfTunnel(name)
	path, e := windows.UTF16PtrFromString(pipe)
	if e != nil {
		return result
	}
	handle, e := windows.CreateFile(path, windows.GENERIC_READ|windows.GENERIC_WRITE, 0, nil, windows.OPEN_EXISTING, 0, 0)
	if e != nil {
		return result
	}
	file := os.NewFile(uintptr(handle), "awg-control")
	defer file.Close()
	if _, e = io.WriteString(file, "get=1\n\n"); e != nil {
		return result
	}
	scanner := bufio.NewScanner(io.LimitReader(file, 1048576))
	var rx, tx uint64
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			break
		}
		pair := strings.SplitN(line, "=", 2)
		if len(pair) != 2 {
			continue
		}
		value, _ := strconv.ParseUint(pair[1], 10, 64)
		if pair[0] == "rx_bytes" {
			rx += value
		}
		if pair[0] == "tx_bytes" {
			tx += value
		}
	}
	if scanner.Err() != nil {
		return result
	}
	result["up"] = true
	result["rx"] = rx
	result["tx"] = tx
	return result
}
func guardPaths(folder string) ([]string, error) {
	if e := protectedDir(folder); e != nil {
		return nil, e
	}
	source, e := os.Executable()
	if e != nil {
		return nil, e
	}
	data, e := os.ReadFile(source)
	if e != nil {
		return nil, e
	}
	target := filepath.Join(folder, "foxway-awg.exe")
	if !strings.EqualFold(source, target) {
		if e = writeBinary(target, data); e != nil {
			return nil, e
		}
	}
	return []string{target, filepath.Join(filepath.Dir(source), "sing-box.exe")}, nil
}
func guardBind(name, folder string, bind bool) error {
	paths, e := guardPaths(folder)
	if e != nil {
		return e
	}
	var luid uint64
	if bind {
		var input struct {
			Protocol string `json:"protocol"`
		}
		if e = json.NewDecoder(io.LimitReader(os.Stdin, 1024)).Decode(&input); e != nil {
			return e
		}
		expected := "FoxWayVless"
		if input.Protocol == "amnezia" {
			expected = name
		} else if input.Protocol != "vless" {
			return errors.New("invalid protocol")
		}
		adapters, e := winipcfg.GetAdaptersAddresses(windows.AF_UNSPEC, winipcfg.GAAFlagDefault)
		if e != nil {
			return e
		}
		for _, a := range adapters {
			if a.FriendlyName() == expected {
				luid = uint64(a.LUID)
				break
			}
		}
		if luid == 0 {
			return errors.New("own TUN not found")
		}
	}
	return guard.Arm(paths, luid)
}

func run() error {
	if len(os.Args) < 2 {
		return errors.New("missing command")
	}
	if os.Args[1] == "service" {
		if len(os.Args) != 3 {
			return errors.New("missing config")
		}
		folder, e := base()
		if e != nil {
			return e
		}
		absolute, e := filepath.Abs(os.Args[2])
		if e != nil || !strings.EqualFold(filepath.Dir(absolute), folder) {
			return errors.New("invalid service path")
		}
		return tunnel.Run(absolute)
	}
	name, e := ownerName()
	if e != nil {
		return e
	}
	folder, e := base()
	if e != nil {
		return e
	}
	switch os.Args[1] {
	case "guard-arm":
		return guardBind(name, folder, false)
	case "guard-bind":
		return guardBind(name, folder, true)
	case "guard-off":
		return guard.Disarm()
	case "guard-status":
		armed, e := guard.Armed()
		if e != nil {
			return e
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]bool{"armed": armed})
	case "up":
		return up(name, folder)
	case "down":
		if e = stop(name); e != nil {
			return e
		}
		_ = os.Remove(filepath.Join(folder, name+".conf.dpapi"))
		return nil
	case "stats":
		return json.NewEncoder(os.Stdout).Encode(stats(name))
	default:
		return errors.New("unknown command")
	}
}
func main() {
	log.SetOutput(io.Discard)
	if run() != nil {
		os.Exit(1)
	}
}
