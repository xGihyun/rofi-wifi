package main

import "core:fmt"
import "core:os/os2"
import "core:strconv"
import "core:strings"

Network :: struct {
	ssid:     string,
	security: string,
}

main :: proc() {
	notify("Fetching list of WiFi connections.")

	allocator := context.allocator

	wifi_list_desc := os2.Process_Desc {
		command = {"nmcli", "-t", "-f", "SSID,SECURITY,BARS", "dev", "wifi", "list"},
	}

	state, stdout, stderr, err := os2.process_exec(wifi_list_desc, allocator)
	if err != nil {
		notify("Failed to fetch list of WiFi connections.")
		return
	}

	lines := strings.split_lines(string(stdout), allocator)
	networks := make([dynamic]Network, allocator)

	for line in lines {
		if len(line) == 0 {
			continue
		}

		net, ok := parse_nmcli_line(line)
		if !ok {
			notify("Failed to parse nmcli line.")
			break
		}

		if len(net.ssid) == 0 {
			continue
		}

		found := false
		for existing in networks {
			if existing.ssid == net.ssid {
				found = true
				break
			}
		}
		if !found {
			append(&networks, net)
		}
	}

	if len(networks) == 0 {
		notify("No Wi-Fi networks found.")
		return
	}

	rofi_input := strings.builder_make(allocator)
	for net in networks {
		strings.write_string(&rofi_input, net.ssid)
		strings.write_byte(&rofi_input, '\n')
	}

	r_in, w_in, pipe_err := os2.pipe()
	if pipe_err != nil {
		notify("Failed to create pipe.")
		return
	}

	_, write_err := os2.write(w_in, rofi_input.buf[:])
	if write_err != nil {
		notify("Failed to write list.")
		return
	}
	os2.close(w_in)

	rofi_desc := os2.Process_Desc {
		command = {"rofi", "-dmenu", "-i", "-p", "Wi-Fi", "-format", "i"},
		stdin   = r_in,
	}
	rofi_state, rofi_stdout, _, rofi_err := os2.process_exec(rofi_desc, allocator)
	if rofi_err != nil {
		notify("Failed to execute rofi.")
		return
	}
	os2.close(r_in)

	idx_str := strings.trim_space(string(rofi_stdout))
	idx, idx_ok := strconv.parse_int(idx_str)
	if !idx_ok {
		return
	}

	selected := networks[idx]
	conn_show_desc := os2.Process_Desc {
		command = {"nmcli", "-t", "-f", "NAME", "connection", "show"},
	}
	show_state, show_stdout, _, show_err := os2.process_exec(conn_show_desc, allocator)
	if show_err != nil {
		notify("Failed to get saved connections.")
		return
	}

	known := false
	known_lines := strings.split_lines(string(show_stdout), allocator)
	for k in known_lines {
		if k == selected.ssid {
			known = true
			break
		}
	}

	if known {
		connect_desc := os2.Process_Desc {
			command = {"nmcli", "connection", "up", "id", selected.ssid},
		}
		_, _, _, err = os2.process_exec(connect_desc, context.temp_allocator)
		if err != nil {
			notify("Failed to connect.")
		}
		return
	}

	sec := strings.trim_space(selected.security)
	if sec == "" || sec == "--" || strings.contains(strings.to_upper(sec), "OPEN") {
		connect_desc := os2.Process_Desc {
			command = {"nmcli", "dev", "wifi", "connect", selected.ssid},
		}
		_, _, _, err = os2.process_exec(connect_desc, context.temp_allocator)
		if err != nil {
			notify("Failed to connect.")
		}
		return
	}

	r_pass_in, w_pass_in, pass_pipe_err := os2.pipe()
	if pass_pipe_err != nil {
		notify("Failed to create pipe.")
		return
	}
	os2.close(w_pass_in)

	pass_prompt := fmt.tprintf("Password for %s", selected.ssid)
	pass_desc := os2.Process_Desc {
		command = {"rofi", "-dmenu", "-p", pass_prompt, "-password"},
		stdin   = r_pass_in,
	}

	pass_state, pass_stdout, _, pass_rofi_err := os2.process_exec(pass_desc, allocator)
	if pass_rofi_err != nil {
		notify("Failed to execute rofi password prompt.")
		return
	}
	os2.close(r_pass_in)

	password := strings.trim_space(string(pass_stdout))
	if len(password) == 0 {
		return
	}

	connect_desc := os2.Process_Desc {
		command = {"nmcli", "dev", "wifi", "connect", selected.ssid, "password", password},
	}
	_, _, _, err = os2.process_exec(connect_desc, context.temp_allocator)
	if err != nil {
		notify(fmt.tprint("Failed to connect to:", selected.ssid))
		return
	}
}

notify :: proc(arg: string) {
	notify_desc := os2.Process_Desc {
		command = {"notify-send", arg},
	}

	state, stdout, stderr, err := os2.process_exec(notify_desc, context.allocator)
	if err != nil {
		fmt.eprintln("Failed to run notify-send:", string(stderr))
		return
	}
}

parse_nmcli_line :: proc(line: string) -> (Network, bool) {
	parts := make([dynamic]string, context.allocator)
	curr := strings.builder_make(context.allocator)

	escape := false
	for i := 0; i < len(line); i += 1 {
		c := line[i]
		if escape {
			strings.write_byte(&curr, c)
			escape = false
		} else if c == '\\' {
			escape = true
		} else if c == ':' {
			append(&parts, strings.to_string(curr))
			curr = strings.builder_make(context.allocator)
		} else {
			strings.write_byte(&curr, c)
		}
	}
	append(&parts, strings.to_string(curr))

	if len(parts) < 3 {
		return Network{}, false
	}

	net := Network {
		ssid     = parts[0],
		security = parts[1],
	}
	return net, true
}
