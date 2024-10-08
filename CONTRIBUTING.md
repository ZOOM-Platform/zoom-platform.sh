# Project conventions and tips

1. Use [ShellCheck](https://www.shellcheck.net/)
2. You need to use this fork of innoextract: https://github.com/doZennn/innoextract
3. You don't need to build anything. Work on `src.sh` directly, it will load `innoextract` from the cwd.
4. Indent with 4 spaces.
5. Variables:
    - Global: `ALL_CAPS` - mostly static values used everywhere
    - Local: `_underscore_prefix_and_lowercase` - only be used within a scope
6. Always use `printf` instead of `echo`.
7. Use LOTS of comments! Scripts are already hard to read especially when it's a bunch of pipes chained together, comments save time trying to figure out what something does.
8. Everything must be as POSIX compliant as you can get it. It's okay to deviate from this within reason.
9. Stick to using tools commonly installed by default on most distros, use fallbacks where appropriate.
10. Final script must be functional when piped into `sh` (e.g. `cat zoom-platform.sh | sh`). An example of something you can't do is using `"$0"` to get the script name.