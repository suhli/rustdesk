//go:build ios

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	tailnet "rustdesk/ios_tailnet"
	"unsafe"
)

var node tailnet.Node

//export rd_tailnet_start
func rd_tailnet_start(dir, config *C.char, key *C.uchar, length C.int) *C.char {
	if err := node.Start(C.GoString(dir), C.GoBytes(unsafe.Pointer(key), length), C.GoString(config)); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export rd_tailnet_stop
func rd_tailnet_stop() *C.char {
	if err := node.Stop(); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export rd_tailnet_status
func rd_tailnet_status() *C.char {
	status, err := node.Status()
	if err != nil {
		data, _ := json.Marshal(map[string]string{"state": "Failed", "error": err.Error()})
		return C.CString(string(data))
	}
	return C.CString(status)
}

//export rd_tailnet_port
func rd_tailnet_port(role C.int, target *C.char) C.int {
	return C.int(node.Port(int(role), C.GoString(target)))
}

//export rd_tailnet_free
func rd_tailnet_free(value *C.char) { C.free(unsafe.Pointer(value)) }

func main() {}
