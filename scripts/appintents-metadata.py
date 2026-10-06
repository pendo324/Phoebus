#!/usr/bin/env python3
"""Writes a widget extension's Metadata.appintents on Linux, in place of
Apple's appintentsmetadataprocessor (macOS only).

Usage:
  scripts/appintents-metadata.py <out/Metadata.appintents> <file.swiftconstvalues>...
  scripts/appintents-metadata.py --self-test

iOS reads this metadata to give configurable widgets their settings;
without it every App Intent widget fails (CHSErrorDomain 1103). The input
is the compiler's const values for the widget target (-emit-const-values,
see Package.swift), which already hold what the metadata needs: each
type's mangled name, its conformances, availability, and the literal
titles, defaults and cases of its parameters and enums.

Only what the widget uses is supported: WidgetConfigurationIntent intents
whose parameters are String, Bool or a String-backed AppEnum, with literal
titles, descriptions and defaults. Anything else is an error rather than a
guess, since iOS rejects metadata it cannot match to the binary.

--self-test regenerates Tests/Fixtures/AppIntents/input.swiftconstvalues
and compares the result with the output of Apple's processor for the same
input (Tests/Fixtures/AppIntents/Metadata.appintents). When the widget's
intents change, that fixture is regenerated on a Mac with
generate-appintents-metadata.sh; until then a mismatch means the
generator has not been verified for the new input.
"""
import json
import sys
from pathlib import Path

TOOLS_VERSION = "17F113"  # the appintentsmetadataprocessor build the format follows
WIDGET_CONFIGURATION = "com.apple.link.systemProtocol.WidgetConfiguration"
STRING, BOOL = 0, 1


class Unsupported(Exception):
    pass


def text(key):
    return {"alternatives": [], "key": key}


def primitive(type_id):
    return {"primitive": {"wrapper": {"typeIdentifier": type_id}}}


def availability(entry):
    """The type's own @available(iOS ...), as Apple writes it: nothing but
    the wildcard for a type without one."""
    annotations = {"LNPlatformNameWildcard": {"introducedVersion": "*"}}
    for attr in entry.get("availabilityAttributes") or []:
        if attr.get("platform") == "iOS" and not attr.get("isUnavailable") and attr.get("introducedVersion"):
            annotations["LNPlatformNameIOS"] = {"introducedVersion": attr["introducedVersion"]}
    return annotations


def literal(value, what):
    """The string of a RawLiteral, or of an InitCall's first argument
    (IntentDescription("..."), TypeDisplayRepresentation(name: "..."))."""
    if value.get("valueKind") == "RawLiteral":
        return value["value"]
    if value.get("valueKind") == "InitCall":
        args = value["value"]["arguments"]
        if args and args[0].get("valueKind") == "RawLiteral":
            for extra in args[1:]:
                if extra.get("valueKind") not in ("NilLiteral", None):
                    raise Unsupported(f"{what}: argument {extra.get('label')} is not supported")
            return args[0]["value"]
    raise Unsupported(f"{what}: expected a string literal, got {value.get('valueKind')}")


def static_property(entry, label):
    return next((p for p in entry.get("properties", []) if p["label"] == label and p["isStatic"] == "true"), None)


def short_name(type_name):
    return type_name.rsplit(".", 1)[-1]


def build_enum(entry):
    name = entry["typeName"]
    raw = next((a["substitutedTypeName"] for a in entry.get("associatedTypeAliases", [])
                if a["typeAliasName"] == "RawValue"), None)
    if raw != "Swift.String":
        raise Unsupported(f"{name}: only String-backed AppEnums are supported (RawValue {raw})")

    type_display = static_property(entry, "typeDisplayRepresentation")
    if type_display is None:
        raise Unsupported(f"{name}: no literal typeDisplayRepresentation")
    display_name = literal(type_display, f"{name}.typeDisplayRepresentation")

    titles = {}
    cases_display = static_property(entry, "caseDisplayRepresentations")
    if cases_display is None or cases_display.get("valueKind") != "Dictionary":
        raise Unsupported(f"{name}: no literal caseDisplayRepresentations")
    for pair in cases_display["value"]:
        if pair["key"].get("valueKind") != "Enum":
            raise Unsupported(f"{name}: caseDisplayRepresentations keys must be cases")
        titles[pair["key"]["value"]["name"]] = literal(pair["value"], f"{name}.{pair['key']['value']['name']}")

    cases = []
    for case in entry.get("cases", []):
        if case["name"] not in titles:
            raise Unsupported(f"{name}.{case['name']}: no display representation")
        cases.append({
            "displayRepresentation": {"title": text(titles[case["name"]])},
            "identifier": case.get("rawValue", case["name"]),
        })
    return {
        "assistantDefinedSchemas": [],
        "availabilityAnnotations": availability(entry),
        "cases": cases,
        "displayTypeName": text(display_name),
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": name,
        "identifier": short_name(name),
        "isSystem": False,
        "mangledTypeName": entry["mangledTypeName"],
        "mangledTypeNameByBundleIdentifier": {},
        "numericFormatTypeName": text(display_name),
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": True},
    }


def unwrap(type_name, prefix):
    return type_name[len(prefix) + 1:-1] if type_name.startswith(prefix + "<") and type_name.endswith(">") else None


def build_parameter(prop, enums, intent):
    name = prop["label"][1:]
    what = f"{intent}.{name}"
    if prop.get("valueKind") != "InitCall":
        raise Unsupported(f"{what}: @Parameter without literal arguments")
    value_type = unwrap(prop["type"], "AppIntents.IntentParameter")
    optional = unwrap(value_type, "Swift.Optional")
    is_optional = optional is not None
    base = optional or value_type

    args = {a["label"]: a for a in prop["value"]["arguments"]}
    title = literal(args.get("title", {}), f"{what} title")
    default = args.get("default", {"valueKind": "NilLiteral"})
    for label, arg in args.items():
        if label not in ("title", "default", "inputConnectionBehavior", "supportedValues") \
                and arg.get("valueKind") != "NilLiteral":
            raise Unsupported(f"{what}: argument {label} is not supported")

    metadata = []
    if base == "Swift.String":
        valuetype = primitive(STRING)
        resolvable = [
            {"kindValue": 0, "valueType": primitive(STRING)},
            {"kindValue": 0, "valueType": {"array": {"wrapper": {
                "capabilities": 3, "memberValueType": primitive(2)}}}},
            {"kindValue": 0, "valueType": primitive(2)},
        ]
        if default["valueKind"] == "RawLiteral":
            metadata = [{"string": {"wrapper": default["value"]}}]
    elif base == "Swift.Bool" and not is_optional:
        valuetype = primitive(BOOL)
        resolvable = [{"kindValue": 0, "valueType": primitive(BOOL)}]
        if default["valueKind"] == "RawLiteral":
            metadata = [{"int": {"wrapper": 1 if default["value"] == "true" else 0}}]
    elif base in enums and not is_optional:
        valuetype = {"linkEnumeration": {"wrapper": {"identifier": short_name(base)}}}
        resolvable = []
        if default["valueKind"] == "Enum":
            case = default["value"]["name"]
            raw = next((c.get("rawValue", c["name"]) for c in enums[base]["cases"] if c["name"] == case), None)
            if raw is None:
                raise Unsupported(f"{what}: default .{case} is not a case of {base}")
            metadata = [{"string": {"wrapper": raw}}]
    else:
        raise Unsupported(f"{what}: parameter type {value_type} is not supported")
    if default["valueKind"] not in ("NilLiteral", "RawLiteral", "Enum") or \
            (default["valueKind"] != "NilLiteral" and not metadata):
        raise Unsupported(f"{what}: default must be a literal")

    return {
        "capabilities": 1 if metadata else 0,
        "dynamicOptionsSupport": 0,
        "inputConnectionBehavior": 0,
        "isInput": False,
        "isOptional": is_optional,
        "name": name,
        "resolvableInputTypes": resolvable,
        "title": text(title),
        "typeSpecificMetadata": ["LNValueTypeSpecificMetadataKeyDefaultValue", metadata[0]] if metadata else [],
        "valueType": valuetype,
    }


def build_intent(entry, enums):
    name = entry["typeName"]
    if "AppIntents.WidgetConfigurationIntent" not in entry["conformances"]:
        raise Unsupported(f"{name}: only WidgetConfigurationIntent intents are supported")
    result = next((a["substitutedTypeName"] for a in entry.get("associatedTypeAliases", [])
                   if a["typeAliasName"] == "PerformResult"), None)
    if result != "Swift.Never":
        raise Unsupported(f"{name}: intents with a perform() result are not supported")
    title = static_property(entry, "title")
    if title is None:
        raise Unsupported(f"{name}: no literal title")
    description = static_property(entry, "description")
    parameters = [build_parameter(p, enums, name) for p in entry.get("properties", [])
                  if p["label"].startswith("_") and p["type"].startswith("AppIntents.IntentParameter<")]
    protocol = [WIDGET_CONFIGURATION, {"empty": {}}]
    return {
        "assistantDefinedSchemaTraits": [],
        "assistantDefinedSchemas": [],
        "authenticationPolicy": 0,
        "availabilityAnnotations": availability(entry),
        "descriptionMetadata": {
            "descriptionText": text(literal(description, f"{name}.description")) if description else text(""),
            "searchKeywords": [],
        },
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": name,
        "identifier": short_name(name),
        "isAuthPolExplicit": False,
        "isDiscoverable": False,
        "mangledTypeName": entry["mangledTypeName"],
        "mangledTypeNameByBundleIdentifier": {},
        "mangledTypeNameByBundleIdentifierV2": {},
        "mangledTypeNameV2": entry["mangledTypeName"],
        "openAppWhenRun": False,
        "outputFlags": 8,
        "parameters": parameters,
        "presentationStyle": 0,
        "requiredCapabilities": [],
        "supportedModes": 1,
        "systemProtocolMetadata": protocol,
        "systemProtocolMetadataV2": protocol,
        "systemProtocols": [WIDGET_CONFIGURATION],
        "title": text(literal(title, f"{name}.title")),
        "typeSpecificMetadata": [],
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": True},
    }


def generate(entries):
    enum_entries = {e["typeName"]: e for e in entries
                    if e["kind"] == "enum" and "AppIntents.AppEnum" in e["conformances"]}
    actions = {}
    for entry in entries:
        if "AppIntents.AppIntent" in entry["conformances"]:
            action = build_intent(entry, enum_entries)
            actions[action["identifier"]] = action
    enums = [build_enum(e) for e in enum_entries.values()]
    for other in entries:
        for protocol in ("AppIntents.AppEntity", "AppIntents.AppShortcutsProvider", "AppIntents.EntityQuery"):
            if protocol in other["conformances"]:
                raise Unsupported(f"{other['typeName']}: {protocol} is not supported")
    return {
        "actions": actions,
        "assistantEntities": [],
        "assistantIntentNegativePhrases": [],
        "assistantIntents": [],
        "autoShortcuts": [],
        "entities": {},
        "enums": enums,
        "generator": {"name": "xcode-tools", "version": TOOLS_VERSION},
        "negativePhrases": [],
        "queries": {},
        "shortcutTileColor": 14,
        "version": 1,
    }


def write(out, metadata):
    out.mkdir(parents=True, exist_ok=True)
    (out / "extract.actionsdata").write_text(
        json.dumps(metadata, sort_keys=True, separators=(",", ":"), ensure_ascii=False))
    (out / "version.json").write_text(
        '{\n  "version" : "3.0",\n  "toolsVersion" : "%s"\n}' % TOOLS_VERSION)


def load(paths):
    entries = []
    for path in paths:
        entries.extend(json.loads(Path(path).read_text()))
    return entries


def normalized(metadata):
    """Apple's processor orders the enums and each parameter's
    resolvableInputTypes arbitrarily (they are sets); compare them sorted."""
    copy = json.loads(json.dumps(metadata))
    copy["enums"] = sorted(copy["enums"], key=lambda e: e["identifier"])
    for action in copy["actions"].values():
        for parameter in action["parameters"]:
            parameter["resolvableInputTypes"].sort(key=lambda t: json.dumps(t, sort_keys=True))
    return copy


def self_test():
    fixtures = Path(__file__).resolve().parent.parent / "Tests/Fixtures/AppIntents"
    expected = json.loads((fixtures / "Metadata.appintents/extract.actionsdata").read_text())
    actual = generate(load([fixtures / "input.swiftconstvalues"]))
    if normalized(actual) != normalized(expected):
        a = json.dumps(normalized(expected), sort_keys=True, indent=1).splitlines()
        b = json.dumps(normalized(actual), sort_keys=True, indent=1).splitlines()
        import difflib
        print("\n".join(list(difflib.unified_diff(a, b, "apple", "generated", lineterm=""))[:60]))
        sys.exit("appintents-metadata: output differs from Apple's for the fixture")
    if (fixtures / "Metadata.appintents/version.json").read_text().strip() != \
            '{\n  "version" : "3.0",\n  "toolsVersion" : "%s"\n}' % TOOLS_VERSION:
        sys.exit("appintents-metadata: version.json differs from Apple's for the fixture")
    print(f"appintents-metadata: matches Apple's output for {len(actual['actions'])} intents "
          f"and {len(actual['enums'])} enums")


def main():
    args = sys.argv[1:]
    if args == ["--self-test"]:
        return self_test()
    if len(args) < 2:
        sys.exit(__doc__.strip().splitlines()[2])
    try:
        metadata = generate(load(args[1:]))
    except Unsupported as error:
        sys.exit(f"appintents-metadata: {error}")
    write(Path(args[0]), metadata)
    print(f"{args[0]}: {len(metadata['actions'])} intents, {len(metadata['enums'])} enums")


if __name__ == "__main__":
    main()
