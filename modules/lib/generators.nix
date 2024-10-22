{ lib }:

{
  toHyprconf = { attrs, indentLevel ? 0, importantPrefixes ? [ "$" ], }:
    let
      inherit (lib)
        all concatMapStringsSep concatStrings concatStringsSep filterAttrs foldl
        generators hasPrefix isAttrs isList mapAttrsToList replicate;

      initialIndent = concatStrings (replicate indentLevel "  ");

      toHyprconf' = indent: attrs:
        let
          sections =
            filterAttrs (n: v: isAttrs v || (isList v && all isAttrs v)) attrs;

          mkSection = n: attrs:
            if lib.isList attrs then
              (concatMapStringsSep "\n" (a: mkSection n a) attrs)
            else ''
              ${indent}${n} {
              ${toHyprconf' "  ${indent}" attrs}${indent}}
            '';

          mkFields = generators.toKeyValue {
            listsAsDuplicateKeys = true;
            inherit indent;
          };

          allFields =
            filterAttrs (n: v: !(isAttrs v || (isList v && all isAttrs v)))
            attrs;

          isImportantField = n: _:
            foldl (acc: prev: if hasPrefix prev n then true else acc) false
            importantPrefixes;

          importantFields = filterAttrs isImportantField allFields;

          fields = builtins.removeAttrs allFields
            (mapAttrsToList (n: _: n) importantFields);
        in mkFields importantFields
        + concatStringsSep "\n" (mapAttrsToList mkSection sections)
        + mkFields fields;
    in toHyprconf' initialIndent attrs;

  toKDL = { }:
    let
      inherit (lib) concatStringsSep splitString mapAttrsToList any;
      inherit (builtins) typeOf replaceStrings elem;

      # ListOf String -> String
      indentStrings = let
        # Although the input of this function is a list of strings,
        # the strings themselves *will* contain newlines, so you need
        # to normalize the list by joining and resplitting them.
        unlines = lib.splitString "\n";
        lines = lib.concatStringsSep "\n";
        indentAll = lines: concatStringsSep "\n" (map (x: "	" + x) lines);
      in stringsWithNewlines: indentAll (unlines (lines stringsWithNewlines));

      # String -> String
      sanitizeString = replaceStrings [ "\n" ''"'' ] [ "\\n" ''\"'' ];

      # OneOf [Int Float String Bool Null] -> String
      literalValueToString = element:
        lib.throwIfNot
        (elem (typeOf element) [ "int" "float" "string" "bool" "null" ])
        "Cannot convert value of type ${typeOf element} to KDL literal."
        (if typeOf element == "null" then
          "null"
        else if element == false then
          "false"
        else if element == true then
          "true"
        else if typeOf element == "string" then
          ''"${sanitizeString element}"''
        else
          toString element);

      # Combined Conversion
      # Set -> String
      nodeToKDLString = node:
        let nodeType = typeOf node;
          optArgsString = lib.optionalString (attrs ? "args")
            (lib.pipe attrs.args [
              (map literalValueToString)
              (lib.concatStringsSep " ")
              (s: s + " ")
            ]);

          optPropsString = lib.optionalString (attrs ? "props")
            (lib.pipe attrs.props [
              (lib.mapAttrsToList
                (name: value: "${name}=${literalValueToString value}"))
              (lib.concatStringsSep " ")
              (s: s + " ")
            ]);
        in if elem nodeType [ "int" "float" "bool" "null" "string" ] then
          ${literalValueToString node}
        else if nodeType == "set" && node.children then
          "${node.id} = ${optArgsString}${optPropsString}{${nodeToKDLString node.children}}"
        else if nodeType == "set" then
          "${node.id} ${optArgsString}${optPropsString}"
        else if nodeType == "list" then
          map nodeToKDLString node
        else
          throw ''
            Cannot convert type `(${nodeType})` to KDL:
              ${node}
          '';
    in attrs: ''
      ${concatStringsSep "\n" (nodeToKDLString attrs)}
    '';

  toSCFG = { }:
    let
      inherit (lib) concatStringsSep mapAttrsToList any;
      inherit (builtins) typeOf replaceStrings elem;

      # ListOf String -> String
      indentStrings = let
        # Although the input of this function is a list of strings,
        # the strings themselves *will* contain newlines, so you need
        # to normalize the list by joining and resplitting them.
        unlines = lib.splitString "\n";
        lines = lib.concatStringsSep "\n";
        indentAll = lines: concatStringsSep "\n" (map (x: "	" + x) lines);
      in stringsWithNewlines: indentAll (unlines (lines stringsWithNewlines));

      # String -> Bool
      specialChars = s:
        any (char: elem char (reserved ++ [ " " "'" "{" "}" ]))
        (lib.stringToCharacters s);

      # String -> String
      sanitizeString =
        replaceStrings reserved [ ''\"'' "\\\\" "\\r" "\\n" "\\t" ];

      reserved = [ ''"'' "\\" "\r" "\n" "	" ];

      # OneOf [Int Float String Bool] -> String
      literalValueToString = element:
        lib.throwIfNot (elem (typeOf element) [ "int" "float" "string" "bool" ])
        "Cannot convert value of type ${typeOf element} to SCFG literal."
        (if element == false then
          "false"
        else if element == true then
          "true"
        else if typeOf element == "string" then
          if element == "" || specialChars element then
            ''"${sanitizeString element}"''
          else
            element
        else
          toString element);

      # Bool -> ListOf (OneOf [Int Float String Bool]) -> String
      toOptParamsString = cond: list:
        lib.optionalString (cond) (lib.pipe list [
          (map literalValueToString)
          (concatStringsSep " ")
          (s: " " + s)
        ]);

      # Attrset Conversion
      # String -> AttrsOf Anything -> String
      convertAttrsToSCFG = name: attrs:
        let
          optParamsString = toOptParamsString (attrs ? "_params") attrs._params;
        in ''
          ${name}${optParamsString} {
          ${indentStrings (convertToAttrsSCFG' attrs)}
          }'';

      # Attrset Conversion
      # AttrsOf Anything -> ListOf String
      convertToAttrsSCFG' = attrs:
        mapAttrsToList convertAttributeToSCFG
        (lib.filterAttrs (name: val: !isNull val && name != "_params") attrs);

      # List Conversion
      # String -> ListOf (OneOf [Int Float String Bool]) -> String
      convertListOfFlatAttrsToSCFG = name: list:
        let optParamsString = toOptParamsString (list != [ ]) list;
        in "${name}${optParamsString}";

      # Combined Conversion
      # String -> Anything  -> String
      convertAttributeToSCFG = name: value:
        lib.throwIf (name == "") "Directive must not be empty"
        (let vType = typeOf value;
        in if elem vType [ "int" "float" "bool" "string" ] then
          "${name} ${literalValueToString value}"
        else if vType == "set" then
          convertAttrsToSCFG name value
        else if vType == "list" then
          convertListOfFlatAttrsToSCFG name value
        else
          throw ''
            Cannot convert type `(${typeOf value})` to SCFG:
              ${name} = ${toString value}
          '');
    in attrs:
    lib.optionalString (attrs != { }) ''
      ${concatStringsSep "\n" (convertToAttrsSCFG' attrs)}
    '';
}
