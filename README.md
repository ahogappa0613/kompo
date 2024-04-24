# Kompo
A tool to pack Ruby and Ruby scripts in one binary. This tool is still under development.

## Installation
```sh
$ gem install kompo
```

## Usage

### prerequisites
Install [komp-vfs](https://github.com/ahogappa0613/kompo-vfs).

#### Homebrew
```sh
$ brew tap ahogappa0613/kompo-vfs https://github.com/ahogappa0613/kompo-vfs.git
$ brew install ahogappa0613/kompo-vfs/kompo-vfs
```

### Building
To build komp-vfs, you need to have cargo installation.
```sh
$ git clone https://github.com/ahogappa0613/kompo-vfs.git
$ cd kompo-vfs
$ cargo build --release
```
Set environment variables
```sh
$ KOMPO_CLI=/path/to/kompo-vfs/target/release/kompo-cli
$ LIB_KOMPO_DIR=/path/to/kompo-vfs/target/release
```

## examples

* hello
  * simple hello world script.
* sinatra_and_sqlite
  * sinatra app with sqlite3 with Gemfile.


## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ahogappa0613/kompo.
