#+build !js
#+vet unused shadowing using-param style semicolon cast explicit-allocators
package nuppu_io

import "core:os"
import "core:log"
import "base:runtime"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	content, err := os.read_entire_file(path, allocator)
	
	if err != nil {
		log.errorf("Failed reading file %v. Error: %v", path, err)
		return {}, false
	}

	return content, true	
}