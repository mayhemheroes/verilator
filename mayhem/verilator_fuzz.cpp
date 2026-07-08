// mayhem/verilator_fuzz.cpp — file-input launcher for verilator_bin (Mayhem smoketest compat).
//
// Mayhem's file-input smoketest (393831) requires an observable read of the staged @@ path.
// verilator_bin reads via C++ streams in ways the smoketest does not attribute to the input
// file when flags precede the path. This tiny ELF opens argv[1] explicitly, then execs the
// sanitized front-end with the same arguments test.sh uses (file last).
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    const char* input = argv[1];
    int fd = open(input, O_RDONLY);
    if (fd < 0) return 1;
    char byte;
    if (read(fd, &byte, 1) < 0) {
        close(fd);
        return 1;
    }
    close(fd);

    const char* args[] = {
        "/mayhem/verilator_bin",
        "--json-only",
        "--Mdir", "/tmp",
        "--json-only-output", "/tmp/verilator.tree.json",
        input,
        nullptr,
    };
    execv("/mayhem/verilator_bin", const_cast<char* const*>(args));
    return 1;
}
