# synced_sounds

MTA:SA resource that plays 2D and 3D sounds for all players, in sync. Players who join later hear the sound from the point it is currently at.

## Dependencies

- [`servertimesync`](https://community.multitheftauto.com/index.php?p=resources&s=details&id=18639) (public MTA community resource by IIYAMA; install the original). It provides the server time used to sync the audio position, and is already listed as an `<include>` in `meta.xml`.

## Exports (server)

All exports return `true` on success. On invalid data they return `false` plus the reason (also sent to the debugscript). `broadcastStopSound` and `broadcastSetSoundVolume` also return `false` when no matching sound exists.

### `broadcastSound3D(data)`

```lua
exports.synced_sounds:broadcastSound3D({
    element = vehicle,        -- or pos = { x, y, z }
    index = 'siren',          -- string or number; identifies the sound
    path = ':my_resource/assets/audio/siren.mp3', -- or a URL
    -- optional
    volume = 1,
    maxDistance = 20,
    minDistance = 5,
    loop = false,
    throttled = false,        -- keep it false for URLs, see "The `throttled` field"
    dimension = 0,
    interior = 0,
    duration = 12.5,          -- seconds; lets the server drop non-looping sounds that already ended
})
```

Calling it again with the same `index` (and the same `element`) replaces the previous sound.

### The `path` field

`path` accepts the same values as MTA's `playSound` / `playSound3D`:

```lua
-- A URL (streamed)
path = 'https://example.com/audio/siren.mp3'

-- A file from another resource, using the `:resourceName/` prefix
path = ':my_resource/assets/audio/siren.mp3'
```

Use the `:resourceName/` form when calling from another resource: the sound is played on the clients, so a plain relative path would be resolved against `synced_sounds`, not against your resource. The file must be listed as a `<file>` in the `meta.xml` of the resource that owns it, so the clients download it.

### The `throttled` field

> **Leave `throttled` as `false` (the default in this resource) when `path` is a URL.**

`throttled` only affects URLs: it makes MTA download the stream with reduced bandwidth. MTA can't seek a throttled stream (`setSoundPosition` fails), so with `throttled = true`:

- the sound still plays for everyone;
- but players who join later hear it **from the beginning** instead of from the current position, so it is no longer in sync.

Note that this default is the opposite of MTA's own `playSound` / `playSound3D`, where `throttled` defaults to `true`. Local files are never throttled, so the field has no effect on them.

The server logs a warning to the debugscript when a URL is broadcast with `throttled = true`.

### `broadcastSound(data)`

2D sound. Fields: `index`, `path`, and optionally `volume`, `loop`, `throttled`, `duration`.

### `broadcastStopSound(index, element)`

Stops the sound and removes it from the list. `element` is optional (omit it for 2D sounds and for 3D sounds placed by position).

### `broadcastSetSoundVolume(volume, index, element)`

Changes the volume of a sound that is already playing, without restarting it.

## Debug

The `/viewSyncedSounds` command lists the active sounds. It needs two things:

1. The `debug` setting set to `true` (edit it in `meta.xml` or in the admin panel's resource settings).
2. The `command.viewSyncedSounds` right in the player's ACL:

```xml
<acl name="Admin">
    <right name="command.viewSyncedSounds" access="true"/>
</acl>
```

## License

[MIT](LICENSE) © cauahzz
