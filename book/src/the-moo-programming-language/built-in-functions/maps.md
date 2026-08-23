## Map Manipulation Functions

When using the functions below, it's helpful to remember that maps are ordered.

### `mapkeys`

```
list mapkeys(map map)
```

returns the keys of the elements of a map.

```
x = ["foo" -> 1, "bar" -> 2, "baz" -> 3];
mapkeys(x)   =>  {"bar", "baz", "foo"}
```

### `mapvalues`

```
list mapvalues(MAP `map` [, ... STR `key`])
```

returns the values of the elements of a map.

If you only want the values of specific keys in the map, you can specify them as optional arguments.
See examples below.

Examples:

```
x = ["foo" -> 1, "bar" -> 2, "baz" -> 3];
mapvalues(x)               =>  {2, 3, 1}
mapvalues(x, "foo", "baz") => {1, 3}
```

### `mapdelete`

```
map mapdelete(map map, key)
```

Returns a copy of map with the value corresponding to key removed. If key is not a valid key, then
E_RANGE is raised.

```
x = ["foo" -> 1, "bar" -> 2, "baz" -> 3];
mapdelete(x, "bar")   ⇒   ["baz" -> 3, "foo" -> 1]
```

### `maphaskey`

```
int maphaskey(MAP map, STR key)
```

Returns 1 if key exists in map. When not dealing with hundreds of keys, this function is faster (and
easier to read) than something like: !(x in mapkeys(map))

### `mapmerge`

```
map mapmerge(map left, map right)
```

Returns the union of `left` and `right`. If both maps contain a key, the result uses the value from
`right`. The function does not change either input map.

```
mapmerge(["a" -> 1, "b" -> 2], ["b" -> 20, "c" -> 30])
    => ["a" -> 1, "b" -> 20, "c" -> 30]
```

### `mapintersection`

```
map mapintersection(map left, map right)
```

Returns the entries from `left` whose keys also exist in `right`. The values in `right` do not
affect the result.

```
mapintersection(["a" -> 1, "b" -> 2], ["b" -> 20, "c" -> 30])
    => ["b" -> 2]
```

### `mapdifference`

```
map mapdifference(map source, list keys)
map mapdifference(map source, map keys)
```

Returns `source` without the specified keys. A list supplies its values as keys. A map supplies its
keys and ignores its values. Missing keys have no effect.

```
mapdifference(["a" -> 1, "b" -> 2, "c" -> 3], {"a", "c"})
    => ["b" -> 2]
mapdifference(["a" -> 1, "b" -> 2, "c" -> 3], ["b" -> 0])
    => ["a" -> 1, "c" -> 3]
```

### `mapcontains`

```
int mapcontains(map source, map wanted [, any default])
```

Returns 1 if `source` contains every key and matching value from `wanted`. Extra entries in `source`
have no effect.

Without `default`, a missing key makes the function return 0. With `default`, the function compares
that value to the wanted value when a key is missing from `source`.

```
mapcontains(["a" -> 1, "b" -> 2], ["a" -> 1])       => 1
mapcontains(["a" -> 1], ["b" -> 0])                 => 0
mapcontains(["a" -> 1], ["b" -> 0], 0)              => 1
```

The optional argument is useful for sparse maps. For example, a planner can treat an absent state
key as zero.

### `mapproject`

```
map mapproject(map source, list keys)
```

Returns the entries from `source` whose keys occur in `keys`. The function ignores missing and
duplicate keys. The result uses normal map key order, not list order.

```
mapproject(["a" -> 1, "b" -> 2, "c" -> 3], {"c", "a", "missing"})
    => ["a" -> 1, "c" -> 3]
```
