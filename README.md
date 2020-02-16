# Sysdigcmd

Sysdigcmd is a utility used to inspect what files where opened by a process during runtime without sacrifising speed.

## Help

```text
This script will log all files opened during runtime of another program into a file.

usage: sudo sysdigcmd.sh OUTPUT_FILE_PATH EXECUTABLE [ARGS ...]

  OUTPUT_FILE_PATH - The file to log the opened files to.
  EXECUTABLE  - The executable to capture.
  ARGS             - [optional] Arguments to apss to executable.

Note: This program requires sudo, but the EXECUTABLE will be run under normal user.
```

# Example

This example shows that if you run `cat /etc/host.conf` it will run as normal
but generate a file in `~/output.out`.

```
$ sudo ./sysdigcmd.sh ~/output.out cat /etc/host.conf
# The "order" line is only used by old versions of the C library.
order hosts,bind
multi on
```
Inspecting the output of `~/output.out` shows some libraries being loaded
followed eventually by `/etc/host.conf` being opened.
```
$ cat ~/output.out
/proc/self/fd
/etc/ld.so.cache
/lib/x86_64-linux-gnu/libc.so.6
/usr/lib/locale/locale-archive
/etc/host.conf
```

## License
[MIT](https://choosealicense.com/licenses/mit/)
