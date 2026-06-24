## Property Information Functions

### `property_info`

**Description:** Retrieves information about a property on an object.\
**Arguments:**

- : The object that has the property `object`
- : The name of the property to get information about `prop-name`

**Returns:** A list containing two elements:

1. The owner of the property (object reference)
2. A string representing the permission flags: 'r' (read), 'w' (write), 'c' (clear)

**Note:** Requires read permission on the property.

### `property_info_hash`

```
str|binary property_info_hash(obj object, str|sym prop-name [, str algorithm] [, int binary])
```

Returns a hash of the value returned by `property_info(object, prop-name)`.

Use this to detect changes to the property's owner or permission flags separately from changes to
the property's value. The optional `algorithm` and `binary` arguments work the same way as they do
for `value_hash()`.

This is a mooR extension.

### `set_property_info`

**Description:** Changes the permission information for a property.\
**Arguments:**

- : The object with the property to modify `object`
- : The name of the property to modify `prop-name`
- : A list containing permission information: `[owner, permissions]` or
  `[owner, permissions, new-name]`
  - : The new owner of the property (object reference) `owner`
  - : A string containing the permission flags (combination of 'r', 'w', 'c') `permissions`
  - `new-name`: Optional new name for the property

`info`

**Returns:** An empty list\
**Note:** Requires appropriate permissions to modify the property.

## Property Management Functions

### `add_property`

**Description:** Adds a new property to an object.\
**Arguments:**

- : The object to add the property to `object`
- : The name for the new property `prop-name`
- : The initial value for the property `value`
- : A list containing permission information (same format as in ) `info`set_property_info``

**Returns:** `none`\
**Note:** Requires appropriate permissions to add properties to the object.

### `delete_property`

**Description:** Removes a property from an object.\
**Arguments:**

- : The object to remove the property from `object`
- : The name of the property to remove `prop-name`

**Returns:** An empty list\
**Note:** Requires ownership of the property or the object.

## Property Value Functions

### `property_value_hash`

```
str|binary property_value_hash(obj object, str|sym prop-name [, str algorithm] [, int binary])
```

Returns a hash of the resolved property value, using the same permission checks as reading the
property. This is useful for detecting whether authored property state changed since some recorded
base revision.

This is a mooR extension.

### `property_metadata_hash`

```
str|binary property_metadata_hash(obj object, str|sym prop-name [, str algorithm] [, int binary])
```

Returns a hash of the map returned by `property_metadata(object, prop-name)`.

Use this when metadata attached to the property is itself part of the state you want to compare.
This is a mooR extension.

### `is_clear_property`

**Description:** Checks if a property is cleared, meaning its value will be resolved transitively
from a parent object through prototype inheritance.\
**Arguments:**

- : The object to check `object`
- : The name of the property to check `prop-name`

**Returns:** A boolean value (true if the property is clear)\
**Note:** Requires read permission on the property.

### `clear_property`

**Description:** Clears a property, making its value be resolved transitively from a parent object
through prototype inheritance.\
**Arguments:**

- : The object with the property to clear `object`
- : The name of the property to clear `prop-name`

**Returns:** An empty list\
**Note:** Requires write permission on the property.

## Property Permissions Explained

Properties in this system use a permission model based on the following flags:

- (read): Controls who can read the property's value **r**
- **w** (write): Controls who can change the property's value
- (clear): Controls who can clear the property, allowing its value to be resolved from parent
  objects **c**

These permissions are represented as a string (e.g., "rwc" for all permissions, "r" for read-only).

## Property Info List Format

Several functions use a property info list format:

- Two-element format: `[owner, permissions]`
- Three-element format: `[owner, permissions, new-name]`

Where:

- is an object reference `owner`
- is a string containing the permission flags (combination of 'r', 'w', 'c') `permissions`
- `new-name` (when present) is a string representing the new name for the property

## Property Inheritance

This system uses prototype-based inheritance for properties:

- When a property is "cleared" on an object, it doesn't store its own value
- Instead, when accessing a cleared property, the system looks for that property on parent/prototype
  objects
- This enables efficient inheritance of property values without duplication
