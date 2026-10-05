# API reference: localization

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Localization](../localization.md).

## Locale codes

A locale code is two or three lowercase letters (`en`, `fr`), optionally followed by `_` or
`-` and a region or variant (`fr_CA`, `pt-BR`). The part before `_` or `-` is the base
language.

## `context:RegisterCatalog(locale, entries)`

Registers the texts of the package for one locale. The catalog is removed when the package
is disabled.

| Parameter | Type | Description |
| --- | --- | --- |
| `locale` | string | Locale code |
| `entries` | table | Key → text, or key → table of plural forms |

- Keys: letters, digits, `_`, `-`, `.`.
- Texts may contain placeholders `{name}` (letters, digits and `_`, starting with a letter or `_`).
- Plural forms: a table with any of `zero`, `one`, `two`, `few`, `many`, `other`; `other` is
  required; every value is a string.

Raises:

| Code | When |
| --- | --- |
| `invalid_value` | Malformed locale code, key, plural table, or a value that is neither a string nor a table |
| `invalid_argument` | `entries` is not a table |
| `invalid_state` | The package already registered a catalog for this locale, or its context is no longer active |

## `context:Translate(key, params, locale)`

Returns the text for `key`, with placeholders replaced.

| Parameter | Type | Description |
| --- | --- | --- |
| `key` | string | Key in the package's catalogs, or `"<package>:<key>"` for another package's catalogs |
| `params` | table, optional | Values for placeholders; `count` also selects the plural form |
| `locale` | string, optional | Preferred locale |

Lookup order, first text found wins: `locale`, its base language, the server language
(`language` in `foundation/config.toml`), its base language, `en`.

Placeholders are replaced with `tostring(params[name])`; a placeholder without a value is kept
as written. For a plural table, the form is chosen from `params.count` (a number) with the
plural rule of the locale whose catalog provided the text; when `count` is missing or the
form is not in the table, `other` is used. Plural rules: English (`one` for 1), French (`one`
for 0 and 1, and any value below 2); other languages use the English rule.

When no catalog has the key, returns `"<package>:<key>"` and logs a warning for the package
that owns the catalog, once per key.

Raises `invalid_argument` if `key` is not a string or `params` is not a table,
`invalid_value` if `key` is empty or `locale` is not a locale code, `invalid_state` if the
context is no longer active.
