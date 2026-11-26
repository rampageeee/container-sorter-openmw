# Patch installation

Install the required upstream mod first. The README in each patch folder identifies the target files and any content-list changes.

For a patch supplied as a `.patch` file, make a separate copy of the upstream files named in its README. Open a terminal in that copy at the directory specified in the instructions. With Git installed, run the two commands below using the path to the patch file. **Git Bash** is available with Git for Windows.

```sh
git apply --check "C:/path/to/changes.patch"
git apply "C:/path/to/changes.patch"
```

If the check fails, compare the upstream version and working directory with the patch’s requirements. Install the changed files as an override with higher file priority in Mod Organizer 2 or a later `data=` entry in `openmw.cfg`. Keep their upstream paths. Standalone overrides and builders have their own installation instructions.

Check each patch README for its validation status. Upstream mod credits and licenses apply to their respective work.
