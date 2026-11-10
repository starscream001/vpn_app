// SPDX-License-Identifier: MIT
// FoxWay persistent WFP guard. WFP ABI/rule helpers retain upstream MIT notices.
package guard

import (
	"fmt"
	"golang.org/x/sys/windows"
	"unsafe"
)

type wfpObjectInstaller func(uintptr) error
type baseObjects struct{ provider, filters windows.GUID }

var provider = windows.GUID{Data1: 0x71b8ca40, Data2: 0xeeaa, Data3: 0x4421, Data4: [8]byte{0x83, 0xa1, 0x42, 0x46, 0x4f, 0x58, 0x57, 0x59}}
var sublayer = windows.GUID{Data1: 0x71b8ca41, Data2: 0xeeaa, Data3: 0x4421, Data4: provider.Data4}
var nextFilter uint32
var dll = windows.NewLazySystemDLL("fwpuclnt.dll")

func key(index uint32) windows.GUID { k := provider; k.Data1 = 0x71b8cb00 + index; return k }
func invoke(name string, args ...uintptr) error {
	r, _, _ := dll.NewProc(name).Call(args...)
	if r != 0 {
		return windows.Errno(r)
	}
	return nil
}
func open() (uintptr, error) {
	var h uintptr
	e := fwpmEngineOpen0(nil, cRPC_C_AUTHN_WINNT, nil, nil, unsafe.Pointer(&h))
	return h, e
}
func fwpmFilterAdd0(h uintptr, f *wtFwpmFilter0, sd uintptr, id *uint64) error {
	if nextFilter >= 256 {
		return fmt.Errorf("guard filter limit")
	}
	f.filterKey = key(nextFilter)
	nextFilter++
	f.flags |= cFWPM_FILTER_FLAG_PERSISTENT
	return rawFwpmFilterAdd0(h, f, sd, id)
}
func remove(h uintptr) error {
	for i := uint32(0); i < 256; i++ {
		k := key(i)
		e := invoke("FwpmFilterDeleteByKey0", h, uintptr(unsafe.Pointer(&k)))
		if e != nil && e != windows.Errno(0x80320003) {
			return e
		}
	}
	return nil
}
func register(h uintptr) error {
	display, e := createWtFwpmDisplayData0("FoxWay persistent protection", "Only FoxWay native cores and the tunnel may connect")
	if e != nil {
		return e
	}
	p := wtFwpmProvider0{providerKey: provider, displayData: *display, flags: 1}
	if e = fwpmProviderAdd0(h, &p, 0); e != nil && e != windows.Errno(0x80320009) {
		return e
	}
	s := wtFwpmSublayer0{subLayerKey: sublayer, displayData: *display, flags: cFWPM_SUBLAYER_FLAG_PERSISTENT, providerKey: &provider, weight: 0xfffe}
	if e = fwpmSubLayerAdd0(h, &s, 0); e != nil && e != windows.Errno(0x80320009) {
		return e
	}
	return nil
}

// Arm atomically replaces ONLY this provider's deterministically keyed filters.
// Persistent objects survive the controller, native core, service and GUI exiting.
func Arm(paths []string, luid uint64) error {
	h, e := open()
	if e != nil {
		return e
	}
	defer fwpmEngineClose0(h)
	return runTransaction(h, func(h uintptr) error {
		if e := register(h); e != nil {
			return e
		}
		if e := remove(h); e != nil {
			return e
		}
		nextFilter = 0
		b := &baseObjects{provider, sublayer}
		for _, p := range paths {
			if e := permitProcess(h, b, 15, p); e != nil {
				return e
			}
		}
		if e := permitLoopback(h, b, 13); e != nil {
			return e
		}
		if luid != 0 {
			if e := permitTunInterface(h, b, 12, luid); e != nil {
				return e
			}
		}
		if e := permitDHCPIPv4(h, b, 12); e != nil {
			return e
		}
		if e := permitDHCPIPv6(h, b, 12); e != nil {
			return e
		}
		if e := permitNdp(h, b, 12); e != nil {
			return e
		}
		return blockAll(h, b, 0)
	})
}
func Disarm() error {
	h, e := open()
	if e != nil {
		return e
	}
	defer fwpmEngineClose0(h)
	return runTransaction(h, remove)
}
func Armed() (bool, error) {
	h, e := open()
	if e != nil {
		return false, e
	}
	defer fwpmEngineClose0(h)
	k := key(0)
	var f uintptr
	e = invoke("FwpmFilterGetByKey0", h, uintptr(unsafe.Pointer(&k)), uintptr(unsafe.Pointer(&f)))
	if e == windows.Errno(0x80320003) {
		return false, nil
	}
	if e != nil {
		return false, e
	}
	fwpmFreeMemory0(unsafe.Pointer(&f))
	return true, nil
}
