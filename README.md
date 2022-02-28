# zemplate

Zemplate is a *WIP* zig templating engine.

The syntax is inspired by text/template from go.

## Examples

### Identifiers

```txt
{{.foo}}
```

Pulls `foo` from struct and inserts it into the template.

if `foo` is `{ "foo": "bar" }` the output would be

```txt
bar
```

### Ranges

```txt
{{ range .foo }}- {{ .bar }}
{{ end }}
```

if `foo` is `{"foo": [{ "bar": "a" }, { "bar": "b" }, { "bar": "c" }]}` then the output would be

```txt
- a
- b
- c

```

### Conditionals

```txt
{{ if .foo }}{{ .bar }}{{ end }}
```

if `foo` is `{"foo": true, "bar": "hello world!"}` then the output would be

```text
hello world!
```

## Notes

I'm open to any and all contributions, be it from code-review, documentation or any form of critique, especially since this is my first zig project.
