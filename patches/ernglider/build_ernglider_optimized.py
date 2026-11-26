#!/usr/bin/env python3
"""Create a five-file ErnGlider override ZIP; never edit the installed mod."""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import urllib.request
import urllib.parse
import zipfile
import sys

REV = '022854aadce519d7fc53deee1c93c13883dc0839'
BASE = 'https://raw.githubusercontent.com/ernmw/ErnGlider/' + REV + '/'
SUB = 'scripts/ErnGlider/'
SHAS = {
    'glider.lua': 'd61f9a02d56da0f28903a8cb651d53e7b6c136b5',
    'surf.lua': 'd951e2c079d9db4252ea17e78afcb61b4ede7981',
    'global.lua': '9395c5e4c10bcbf9313c018f79e0a7caeae57112',
    'blurshader.lua': 'b31adbff4abbd597ec9bca328e35973296a47087',
    'updraftshader.lua': '8e34843ba4ea732366ad66be4dcec12eaa0c4743',
}
# Each replacement must match exactly once. Whitespace is intentional.
PATCHES = {
    'glider.lua': [
        ('local fatigueDebt = 0', 'local fatigueDebt = 0\nlocal rayCastDelay = 0'),
        ('local rayCastDelay = 0\n\n-- taitechnic', '-- taitechnic'),
        ('    persist.applied = false\n    persist.appliedDuration = 0',
         '    persist.applied = false\n    rayCastDelay = 0\n    core.sendGlobalEvent(MOD_NAME .. "onGlideEnd", { player = pself.object })\n    persist.appliedDuration = 0'),
        ('    persist.applied = true\n    print("Applying glider...")',
         '    persist.applied = true\n    rayCastDelay = 0\n    print("Applying glider...")'),
        ('local function onUpdraft(data)\n    if data.started then',
         'local function onUpdraft(data)\n    if not persist.applied then return end\n    if data.started then'),
        ('    local inFirst = camera.getMode() == camera.MODE.FirstPerson',
         '    if not persist.applied then\n        inFirstPerson = nil\n        return\n    end\n    local inFirst = camera.getMode() == camera.MODE.FirstPerson'),
        ('        if rayCastDelay > 0.3 then\n            local touchResult',
         '        if rayCastDelay >= 0.3 then\n            rayCastDelay = rayCastDelay % 0.3\n            local touchResult'),
        ('''            -- check for updrafts
            core.sendGlobalEvent(MOD_NAME .. "onDoUpdraft", {
                player = pself,
                dt = dt
            })
        end''', '''        end
        -- Integrate updraft movement at the simulation rate. Collision checks
        -- are throttled independently, so the teleport displacement keeps its dt.
        core.sendGlobalEvent(MOD_NAME .. "onDoUpdraft", {
            player = pself,
            dt = dt
        })'''),
    ],
    'surf.lua': [
        ('local blurShader             = blur.NewBlurShader()',
         'local conditionDebt = 1\nlocal rayCastDelay = 0\n\nlocal blurShader             = blur.NewBlurShader()'),
        ('local conditionDebt = 1\nlocal rayCastDelay = 0\n\nlocal function onUpdate(dt)', 'local function onUpdate(dt)'),
        ('    persist.applied = false\n    persist.appliedDuration = 0',
         '    persist.applied = false\n    rayCastDelay = 0\n    conditionDebt = 1\n    persist.appliedDuration = 0'),
        ('    persist.applied = true\n    persist.momentum = startMomentum',
         '    persist.applied = true\n    rayCastDelay = 0\n    conditionDebt = 1\n    persist.momentum = startMomentum'),
        ('''    -- make more gates
    persist.gatePositions = chimgates.getAllGatePositions()
    settings.debugPrint("Spawned " .. tostring(#persist.gatePositions) .. " CHIM gates.")
    spawnCHIMGates()''', '''    -- Gate placement uses raycasts and navigation queries. Do it only if wanted.
    persist.gatePositions = {}
    persist.touchedGates = {}
    if settings.surf.chimTricky then
        persist.gatePositions = chimgates.getAllGatePositions()
        settings.debugPrint("Spawned " .. tostring(#persist.gatePositions) .. " CHIM gates.")
        spawnCHIMGates()
    end'''),
        ('        if rayCastDelay > 0.3 then', '        if rayCastDelay >= 0.3 then\n            rayCastDelay = rayCastDelay % 0.3'),
        ('''        chimtricky.display({
            dt = dt,
            speed = avgSpeed,
            conditionRatio = types.Item.itemData(getShield()).condition / persist.activeShieldRecord.health,
            fatigueRatio = fatigueStat.current / fatigueStat.base,
            momentumRatio = util.remap(persist.momentum, kickoutMinimumMomentum, 1, 0, 1),
            points = calcPoints(false),
            newToasts = newToasts,
        })
    else
        -- not currently surfing
        conditionDebt = 1''', '''        if settings.surf.chimTricky then
            chimtricky.display({
                dt = dt,
                speed = avgSpeed,
                conditionRatio = types.Item.itemData(getShield()).condition / persist.activeShieldRecord.health,
                fatigueRatio = fatigueStat.current / fatigueStat.base,
                momentumRatio = util.remap(persist.momentum, kickoutMinimumMomentum, 1, 0, 1),
                points = calcPoints(false),
                newToasts = newToasts,
            })
        else
            -- Hide an existing HUD if the setting was changed mid-run.
            chimtricky.display(nil)
        end'''),
    ],
    'global.lua': [
        ('local fieldsByCell                    = {}',
         'local fieldsByCell                    = {}\n-- One negative-cache entry, rather than a permanent empty table per cell.\nlocal emptyCellId = nil'),
        ('    if not fieldsByCell[data.player.cell.id] then',
         '    local cellId = data.player.cell.id\n    local field = fieldsByCell[cellId]\n    if not field and emptyCellId ~= cellId then'),
        ('''        fieldsByCell[data.player.cell.id] = kdf
    end

    -- return val
    local updraftVal = util.clamp(fieldsByCell[data.player.cell.id]:max(data.player.position), 0, 1)''', '''        if next(kdf.kernels) then
            fieldsByCell[cellId] = kdf
            field = kdf
        else
            emptyCellId = cellId
        end
    end

    -- No allocations or kernel evaluation on empty-cell cache hits.
    local updraftVal = field and util.clamp(field:max(data.player.position), 0, 1) or 0'''),
        ('''    else
        local ended = false
        if updraftingPlayers[data.player.id] then
            updraftingPlayers[data.player.id] = false
            ended = true
        end
        data.player:sendEvent(MOD_NAME .. "onUpdraft", { value = 0, ended = ended })
    end
end''', '''    elseif updraftingPlayers[data.player.id] then
        -- Only notify the player when actually leaving an updraft.
        updraftingPlayers[data.player.id] = nil
        data.player:sendEvent(MOD_NAME .. "onUpdraft", { value = 0, ended = true })
    end
end

local function onGlideEnd(data)
    updraftingPlayers[data.player.id] = nil
end'''),
        ('        [MOD_NAME .. \'onDoUpdraft\'] = onDoUpdraft,',
         '        [MOD_NAME .. \'onDoUpdraft\'] = onDoUpdraft,\n        [MOD_NAME .. \'onGlideEnd\'] = onGlideEnd,'),
        ('    fieldsByCell[data.self.cell.id] = nil',
         '    fieldsByCell[data.self.cell.id] = nil\n    if emptyCellId == data.self.cell.id then emptyCellId = nil end'),
    ],
    'blurshader.lua': [
        ('function BlurShaderFunctions.update(self, strength)\n',
         'function BlurShaderFunctions.update(self, strength)\n    if not self.enabled then return end\n'),
    ],
    'updraftshader.lua': [
        ('function UpdraftShaderFunctions.update(self, strength, dt)\n',
         'function UpdraftShaderFunctions.update(self, strength, dt)\n    if not self.enabled then return end\n'),
    ],
}

NOTICE = '-- Modified 2026-11-25: targeted idle/active performance changes; original license retained.\n'

def blob_sha(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()


def verified_text(name, data):
    # Accept a CRLF checkout only if normalization restores the exact upstream blob.
    if blob_sha(data) != SHAS[name]:
        data = data.replace(b'\r\n', b'\n')
    if blob_sha(data) != SHAS[name]:
        raise ValueError(f'{name}: source differs from pinned commit {REV[:7]}; no output written.')
    return data.decode('utf-8')


def patch(name, source):
    for old, new in PATCHES[name]:
        if source.count(old) != 1:
            raise ValueError(f'{name}: expected exactly one patch anchor: {old[:100]!r}')
        source = source.replace(old, new, 1)
    return (NOTICE + source).encode('utf-8')


def download(rel):
    request = urllib.request.Request(BASE + urllib.parse.quote(rel), headers={'User-Agent': 'ErnGlider-local-override-builder/1.0'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def locate(root):
    root = root.expanduser().resolve()
    for path in (root / '00 Core' / SUB, root / SUB, root):
        if all((path / f).is_file() for f in SHAS):
            return path
    raise ValueError(f'Cannot find all five original Lua files under {root}. Select the mod root, 00 Core, or scripts/ErnGlider.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Optional existing extracted ErnGlider mod folder. Without this, fetch exact upstream files from GitHub.')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().with_name('ErnGlider_optimized_override.zip'))
    args = parser.parse_args()
    path = locate(args.source) if args.source else None
    changed = {}
    for name in SHAS:
        raw = (path / name).read_bytes() if path else download('00 Core/' + SUB + name)
        changed[name] = patch(name, verified_text(name, raw))
        print('Verified and patched:', name)
    if args.output.exists():
        raise FileExistsError(f'Output already exists: {args.output}. Choose another --output or remove the old ZIP.')
    # All checks completed before writing any ZIP. No installed files are touched.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, 'x', compression=zipfile.ZIP_DEFLATED) as z:
        for name, contents in changed.items():
            z.writestr(SUB + name, contents)
        z.writestr('README-ErnGlider-optimization.txt', 'ErnGlider performance override\nBased on upstream commit ' + REV + '\nOriginal author: Erin Pentecost. AGPL-3.0-or-later.\nSource: https://github.com/ernmw/ErnGlider/tree/' + REV + '\nInstall as a higher-priority data directory or overwrite matching scripts in 00 Core. No plugin or asset changes.\nRuntime behavior must be tested in OpenMW 0.51.\n')
        if path:
            for parent in [path, *path.parents]:
                lic = parent / 'LICENSE'
                if lic.is_file() and blob_sha(lic.read_bytes()) == '0ad25db4bd1d86c452db3f9602ccdbe172438f52':
                    z.writestr('LICENSE', lic.read_bytes())
                    break
        else:
            # Include upstream license when using remote sources.
            # Failure here is nonfatal; every Lua file retains its license header.
            try:
                lic = download('LICENSE')
                if blob_sha(lic) == '0ad25db4bd1d86c452db3f9602ccdbe172438f52':
                    z.writestr('LICENSE', lic)
            except Exception as e:
                print('Note: could not fetch full upstream license:', e, file=sys.stderr)
    print('\nCreated:', args.output.resolve())
    print('Install as an override mod or extract over the original data directory.')

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('ERROR:', exc, file=sys.stderr)
        sys.exit(1)
