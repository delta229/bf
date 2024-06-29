# BF

Simple BrainFuck interpreter written in Zig. Usage:

```bash
$ bf [file]
```

If no file is specified, the REPL is started.

REPL Commands:
- quit: Exit the program
- reset: Reset the interpreter state (zero cells and data pointer)
- dump: Print the interpreter state
- debug: Dump state after every command
- id: Dump state after every instruction (if debug mode is enabled)
