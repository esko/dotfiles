{ lib }:

{
  # Soft attribute lookup for packages that may be missing across nixpkgs
  # channels. Prefer required packages in `with pkgs; [ ... ]` when an attr is
  # part of the supported profile so missing names fail evaluation loudly.
  optionalPackages = pkgs: names:
    builtins.concatLists (map
      (name: lib.optional (builtins.hasAttr name pkgs) (builtins.getAttr name pkgs))
      names);

  # Like optionalPackages, but skip packages whose license is not free when the
  # current nixpkgs instance would refuse them (shared profile default).
  optionalFreePackages = pkgs: names:
    builtins.concatLists (map
      (name:
        if builtins.hasAttr name pkgs then
          let package = builtins.getAttr name pkgs;
          in lib.optional (lib.attrByPath [ "meta" "license" "free" ] true package) package
        else
          [ ])
      names);
}
