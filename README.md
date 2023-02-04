# Decompile

## Installation

```bash
$ mix archive.install github michalmuskala/decompile
```

## Installing a forked version

```bash
$ mix archive.install github mindreframer/decompile
```

## Usage

```bash
# to Elixir and pipe to stdout
$ mix decompile ElixirModule --to ex --stdout
$ mix decompile ElixirModule --to erlang
$ mix decompile ElixirModule --to asm
$ mix decompile ElixirModule --to core
```

## Dev

```bash
$ git clone https://github/michalmuskala/decompile
$ cd decompile
# ... make changes ...
$ mix archive.install
# ... test locally
```
