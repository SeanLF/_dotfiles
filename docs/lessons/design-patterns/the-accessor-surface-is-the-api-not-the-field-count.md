---
title: When you change an internal data shape, what costs you is the accessors that stop working, not the fields you added
date: 2026-08-15
category: design-patterns
module: any change to a struct/tuple/array that other code reads
problem_type: best_practice
severity: high
applies_when:
  - You are adding a field to a tuple, struct, or array that other code reads
  - You have decided an internal data shape is "public by accident" and therefore safe to change
  - A value-object refactor looks obviously cleaner than the tuple it replaces
  - You are migrating off ruby2_keywords, Hash.ruby2_keywords_hash, or a similar implicit marker
tags:
  [api-compatibility, migration, data-modelling, ecosystem, deprecation, ruby]
---

## The lesson

Adding a field to a shared data shape is cheap. Changing what the shape _responds to_ is
expensive. Before restructuring, enumerate the accessors consumers actually call — `[]`,
`==`, `is_a?`, destructuring — and rank candidates by which of those survive. Field count
is nearly irrelevant; it is the accessor surface that is the API.

Corollary: the time to make a shape an opaque object is **before** third parties start
indexing into it. After that, the object is the expensive option no matter how much better
it reads.

## The measurement

Sinatra stores `Sinatra::Base.use` as `[middleware, args, block]` and relies on
`ruby2_keywords` to replay the trailing Hash as keywords. Ruby removes that in 4.4
(bugs.ruby-lang.org/issues/22205). Three candidates, each consumer expression executed
verbatim rather than reasoned about:

| consumer call site                                  | 4-slot tuple | `Data` object | Hash-subclass marker |
| --------------------------------------------------- | ------------ | ------------- | -------------------- |
| New Relic `info[0] == clazz` — boot path, unrescued | ok           | **raises**    | ok                   |
| Honeybadger `m[0] == klass` — boot path, unrescued  | ok           | **raises**    | ok                   |
| solana pay-kit `entry[0]`                           | ok           | **raises**    | ok                   |
| ruby-debug-agent `mw[1..-1]` — inside `rescue`      | shifts       | empty + error | ok                   |
| ruby-debug-agent `is_a?(Array)` — inside `rescue`   | ok           | silent skip   | ok                   |
| appsignal `include([K, [], nil])` — spec only       | fails        | fails         | ok                   |

The `Data` column is not a property of value objects; it is a property of _that_ candidate
lacking `[]` and a lenient `==`. A four-slot `Struct` — more fields, not fewer — clears both
boot-path rows because `Struct` keeps `[]`. That is the whole point: the column that
predicts breakage is "does `[]` still work", not "how many fields".

Two things I got wrong by not checking:

- **`include Enumerable` + one `each`** buys `first`/`to_a`/`count`/`map`/`include?` — the
  long tail I had called an unbounded shim list. It does not buy `[]` or `size`, which are
  the two anyone calls.
- **`is_a?(Array)` cannot be faked.** `case x when Array` goes through `Module#===` in C
  and never dispatches to a Ruby-defined `is_a?`.

## What Rails actually did, and when

I asserted Rails' `MiddlewareStack::Middleware` had carried `klass/args/kwargs/block` for
years. It had not. `attr_reader :args, :block, :klass` held for fifteen years; `kwargs` was
added in **26b883326, 2026-08-08** — one week before this lesson — for this same Ruby
ticket. The design it replaced was
`args << Hash.ruby2_keywords_hash(kwargs) unless kwargs.empty?`: the marker shape, which
Rails deliberately abandoned.

So Rails is precedent for the explicit slot, not for the marker. But the reason Rails could
add a slot cheaply is the lesson restated: its entry was already an object with named
readers and no positional consumers, and the same commit marked it `:nodoc:` to say so.
Sinatra cannot follow directly, because its entry is an Array that at least five gems index
into. Rails' end state is right; Rails' freedom to get there in one step does not transfer.

## The shape

- Grep consumers for the _accessors_, not the type. `[0]`, `[1..-1]`, `==`, `is_a?`,
  `|a, b, c|` destructuring. That list, not the field list, is your compatibility contract.
- Check whether a break is loud. Two of the six reads above sit inside a `rescue`, so they
  degrade to an error string rather than propagating — a quieter and worse failure than the
  crash I first recorded.
- A malformed search query returns zero rows, not an error. `gh search code
'repo:x/y term'` yields nothing; `gh search code term --repo x/y` yields 32. I concluded
  the tool was broken and hand-picked repos instead. See
  [[a-harness-that-measures-the-wrong-thing-still-exits-0]].
- Scope "non-breaking" to what you tested. The marker survives `==`, `inspect`, `hash`, and
  positional access, but `Marshal` and YAML embed the subclass name and fail to load where
  the library is absent. Unreachable in all fourteen consumers checked — still not "nothing
  changed".

## Related

- [[a-cleaner-design-can-measure-worse-than-the-patch-it-replaces]]
- [[a-harness-that-measures-the-wrong-thing-still-exits-0]]
- [[a-passing-test-may-be-asserting-nothing]]
