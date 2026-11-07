# Adaptive AI Code Assistant for COBOL

An AI code assistant that explains how COBOL code works with the learning style of developers, built as a proof of concept aligned with IBM's COBOL modernization efforts.

## Installation

Clone the repository, then run the installer for your platform from the repository folder:

| Platform      | Command                                                     |
| ------------- | ----------------------------------------------------------- |
| macOS / Linux | `./install.sh`                                              |
| Windows       | double-click `install.cmd`, or run `install.cmd` in a terminal |

The installer:

1. Checks your computer (OS, RAM, disk space, and GPU).
2. Installs Docker if it's missing (Docker Desktop on macOS and Windows; Docker Engine on Linux).
3. Picks the fastest way to run the model:

   | Your hardware                | Where Granite runs                                         |
   | ---------------------------- | ---------------------------------------------------------- |
   | NVIDIA GPU (Linux, Windows)  | Ollama in Docker on the GPU (sets up the NVIDIA Container Toolkit on Linux) |
   | AMD GPU (Linux)              | Ollama's ROCm image in Docker                              |
   | AMD GPU (Windows)            | Ollama installed on Windows (Docker can't use AMD GPUs there) |
   | Mac                          | Ollama installed on macOS, using the Apple GPU (Metal)     |
   | No usable GPU                | Ollama in Docker on the CPU (slower)                       |

4. Installs VS Code if you don't have a compatible editor (VS Code, Cursor, VSCodium, and Windsurf are detected).
5. Downloads the Granite models (~6 GB) with a progress bar. Meanwhile it builds the backend and the extension in the background.
6. Starts everything and waits until the tutor is ready.
7. Installs the CobolTutor extension into every editor it found.

It's safe to run again: finished steps are skipped, and models aren't downloaded twice.
Useful options (the same on every platform):

```bash
./install.sh --help          # all options
./install.sh --yes           # no questions
./install.sh --dry-run       # show what would happen, change nothing
./install.sh --cpu           # ignore the GPU
./install.sh --ollama docker # on a Mac, run Ollama in Docker instead (CPU only)
```

The installer saves its choice in `coboltutor/.env` (`COMPOSE_FILE=...`), so a plain
`docker compose up -d` in `coboltutor/` keeps using the same setup. Logs from each run
are kept in `.install-logs/`.
## Usage

1. Open a COBOL file in VS Code.
2. Open the assistant's chat panel.
3. Select a section of code and ask for an explanation
4. Choose or adjust the explanation style that fits how you like to learn.

> This project is in early development, so some features described here are still being built.


## Contributing

Our guide for contributing can be found in our [contributing guide](CONTRIBUTING.md)
