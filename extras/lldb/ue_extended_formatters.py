"""
Extended LLDB type formatters for Unreal Engine types.

Supplements Epic's built-in UEDataFormatters which only cover ~15 types.
These formatters cover high-priority types from Unreal.natvis that are
frequently inspected during gameplay debugging.

Usage (loaded automatically by unrealium.nvim debug module):
    command script import "/path/to/ue_extended_formatters.py"
"""

import lldb


def __lldb_init_module(debugger, internal_dict):
    """Register all type summaries and synthetic providers."""
    cat = debugger.GetDefaultCategory()
    cat.SetEnabled(True)

    # TSharedPtr / TSharedRef
    debugger.HandleCommand(
        'type summary add -x "^TSharedPtr<" -F ue_extended_formatters.TSharedPtr_summary'
    )
    debugger.HandleCommand(
        'type summary add -x "^TSharedRef<" -F ue_extended_formatters.TSharedRef_summary'
    )

    # TUniquePtr
    debugger.HandleCommand(
        'type summary add -x "^TUniquePtr<" -F ue_extended_formatters.TUniquePtr_summary'
    )

    # TOptional
    debugger.HandleCommand(
        'type summary add -x "^TOptional<" -F ue_extended_formatters.TOptional_summary'
    )

    # TObjectPtr / FObjectPtr
    debugger.HandleCommand(
        'type summary add -x "^TObjectPtr<" -F ue_extended_formatters.TObjectPtr_summary'
    )
    debugger.HandleCommand(
        "type summary add FObjectPtr -F ue_extended_formatters.FObjectPtr_summary"
    )

    # TSoftObjectPtr
    debugger.HandleCommand(
        'type summary add -x "^TSoftObjectPtr<" -F ue_extended_formatters.TSoftObjectPtr_summary'
    )

    # FText
    debugger.HandleCommand(
        "type summary add FText -F ue_extended_formatters.FText_summary"
    )

    # FGuid
    debugger.HandleCommand(
        "type summary add FGuid -F ue_extended_formatters.FGuid_summary"
    )

    # Math types
    debugger.HandleCommand(
        'type summary add -x "^UE::Math::TVector<" -F ue_extended_formatters.TVector_summary'
    )
    debugger.HandleCommand(
        'type summary add -x "^UE::Math::TVector4<" -F ue_extended_formatters.TVector4_summary'
    )
    debugger.HandleCommand(
        'type summary add -x "^UE::Math::TQuat<" -F ue_extended_formatters.TQuat_summary'
    )
    debugger.HandleCommand(
        "type summary add FRotator -F ue_extended_formatters.FRotator_summary"
    )
    debugger.HandleCommand(
        'type summary add -x "^UE::Math::TRotator<" -F ue_extended_formatters.FRotator_summary'
    )
    debugger.HandleCommand(
        'type summary add -x "^UE::Math::TTransform<" -F ue_extended_formatters.TTransform_summary'
    )

    # TFunction / TFunctionRef
    debugger.HandleCommand(
        'type summary add -x "^TFunction<" -F ue_extended_formatters.TFunction_summary'
    )
    debugger.HandleCommand(
        'type summary add -x "^TFunctionRef<" -F ue_extended_formatters.TFunction_summary'
    )

    # TStringView
    debugger.HandleCommand(
        'type summary add -x "^TStringView<" -F ue_extended_formatters.TStringView_summary'
    )

    # FGameplayTagContainer
    debugger.HandleCommand(
        "type summary add FGameplayTagContainer -F ue_extended_formatters.FGameplayTagContainer_summary"
    )

    print("[unrealium] Extended UE LLDB formatters loaded ({} types)".format(16))


# --- TSharedPtr / TSharedRef ---


def _get_shared_ptr_object(valobj):
    """Extract the Object pointer from a TSharedPtr/TSharedRef."""
    obj = valobj.GetChildMemberWithName("Object")
    if not obj.IsValid():
        return None, None
    ptr_val = obj.GetValueAsUnsigned(0)
    if ptr_val == 0:
        return None, None

    # Try to get reference count from SharedReferenceCount
    ref_count = None
    rc_member = valobj.GetChildMemberWithName("SharedReferenceCount")
    if rc_member.IsValid():
        rc_ptr = rc_member.GetChildMemberWithName("ReferenceController")
        if rc_ptr.IsValid() and rc_ptr.GetValueAsUnsigned(0) != 0:
            shared_count = rc_ptr.GetChildMemberWithName("SharedReferenceCount")
            if shared_count.IsValid():
                ref_count = shared_count.GetValueAsUnsigned(0)

    return obj, ref_count


def TSharedPtr_summary(valobj, internal_dict):
    obj, ref_count = _get_shared_ptr_object(valobj)
    if obj is None:
        return "nullptr"
    summary = obj.GetSummary() or ""
    rc_str = " (refs={})".format(ref_count) if ref_count is not None else ""
    return "{{ptr=0x{:x}{}{}}}".format(
        obj.GetValueAsUnsigned(0), rc_str, " " + summary if summary else ""
    )


def TSharedRef_summary(valobj, internal_dict):
    obj, ref_count = _get_shared_ptr_object(valobj)
    if obj is None:
        return "<invalid>"
    summary = obj.GetSummary() or ""
    rc_str = " (refs={})".format(ref_count) if ref_count is not None else ""
    return "{{ref=0x{:x}{}{}}}".format(
        obj.GetValueAsUnsigned(0), rc_str, " " + summary if summary else ""
    )


# --- TUniquePtr ---


def TUniquePtr_summary(valobj, internal_dict):
    ptr = valobj.GetChildMemberWithName("Ptr")
    if not ptr.IsValid():
        return "nullptr"
    ptr_val = ptr.GetValueAsUnsigned(0)
    if ptr_val == 0:
        return "nullptr"
    summary = ptr.GetSummary() or ""
    return "{{0x{:x}{}}}".format(ptr_val, " " + summary if summary else "")


# --- TOptional ---


def TOptional_summary(valobj, internal_dict):
    is_set = valobj.GetChildMemberWithName("bIsSet")
    if not is_set.IsValid():
        # Try alternate layout
        is_set = valobj.GetChildMemberWithName("bHasValue")

    if not is_set.IsValid():
        return "<unknown layout>"

    if not is_set.GetValueAsUnsigned(0):
        return "unset"

    value = valobj.GetChildMemberWithName("Value")
    if not value.IsValid():
        return "set (value unavailable)"
    summary = value.GetSummary() or value.GetValue() or ""
    return "{{{}}}".format(summary)


# --- TObjectPtr / FObjectPtr ---


def _resolve_object_ptr(valobj):
    """Resolve the UObject* from a TObjectPtr/FObjectPtr handle."""
    handle = valobj.GetChildMemberWithName("Handle")
    if not handle.IsValid():
        # Direct pointer layout
        obj_ptr = valobj.GetChildMemberWithName("ObjectPtr")
        if obj_ptr.IsValid():
            return obj_ptr
        return None

    # In packaged builds, Handle is the raw pointer
    ptr_val = handle.GetValueAsUnsigned(0)
    if ptr_val == 0:
        return None

    # Try to interpret as UObject*
    target = handle.GetProcess().GetTarget()
    uobject_type = target.FindFirstType("UObject")
    if uobject_type.IsValid():
        return handle.Cast(uobject_type.GetPointerType())
    return None


def TObjectPtr_summary(valobj, internal_dict):
    obj = _resolve_object_ptr(valobj)
    if obj is None or obj.GetValueAsUnsigned(0) == 0:
        return "nullptr"
    summary = obj.GetSummary() or ""
    return "{{0x{:x}{}}}".format(
        obj.GetValueAsUnsigned(0), " " + summary if summary else ""
    )


def FObjectPtr_summary(valobj, internal_dict):
    return TObjectPtr_summary(valobj, internal_dict)


# --- TSoftObjectPtr ---


def TSoftObjectPtr_summary(valobj, internal_dict):
    soft_path = valobj.GetChildMemberWithName("ObjectID")
    if not soft_path.IsValid():
        soft_path = valobj.GetChildMemberWithName("SoftObjectPath")
    if not soft_path.IsValid():
        return "<unavailable>"

    asset_path = soft_path.GetChildMemberWithName("AssetPath")
    if asset_path.IsValid():
        pkg = asset_path.GetChildMemberWithName("PackageName")
        asset = asset_path.GetChildMemberWithName("AssetName")
        pkg_summary = pkg.GetSummary() if pkg.IsValid() else ""
        asset_summary = asset.GetSummary() if asset.IsValid() else ""
        if pkg_summary or asset_summary:
            return "{}.{}".format(
                pkg_summary or "?", asset_summary or "?"
            )

    # Legacy SubPathString layout
    path_str = soft_path.GetChildMemberWithName("AssetPathName")
    if path_str.IsValid():
        return path_str.GetSummary() or "<empty>"

    return "<unavailable>"


# --- FText ---


def FText_summary(valobj, internal_dict):
    text_data = valobj.GetChildMemberWithName("TextData")
    if not text_data.IsValid():
        return "<empty>"

    ptr_val = text_data.GetValueAsUnsigned(0)
    if ptr_val == 0:
        return "<empty>"

    # Dereference the TSharedRef<ITextData>
    deref = text_data.Dereference()
    if not deref.IsValid():
        return "<unavailable>"

    # Try to get the cached string
    local_str = deref.GetChildMemberWithName("LocalizedString")
    if local_str.IsValid():
        summary = local_str.GetSummary()
        if summary:
            return summary

    # Try display string
    display = deref.GetChildMemberWithName("DisplayString")
    if display.IsValid():
        summary = display.GetSummary()
        if summary:
            return summary

    return "<text data at 0x{:x}>".format(ptr_val)


# --- FGuid ---


def FGuid_summary(valobj, internal_dict):
    a = valobj.GetChildMemberWithName("A").GetValueAsUnsigned(0)
    b = valobj.GetChildMemberWithName("B").GetValueAsUnsigned(0)
    c = valobj.GetChildMemberWithName("C").GetValueAsUnsigned(0)
    d = valobj.GetChildMemberWithName("D").GetValueAsUnsigned(0)
    return "{{{:08X}-{:04X}-{:04X}-{:04X}-{:04X}{:08X}}}".format(
        a, (b >> 16) & 0xFFFF, b & 0xFFFF, (c >> 16) & 0xFFFF, c & 0xFFFF, d
    )


# --- Math types ---


def TVector_summary(valobj, internal_dict):
    x = valobj.GetChildMemberWithName("X")
    y = valobj.GetChildMemberWithName("Y")
    z = valobj.GetChildMemberWithName("Z")
    if not all(m.IsValid() for m in [x, y, z]):
        return "<unavailable>"
    return "{{X={}, Y={}, Z={}}}".format(
        x.GetValue() or "?", y.GetValue() or "?", z.GetValue() or "?"
    )


def TVector4_summary(valobj, internal_dict):
    x = valobj.GetChildMemberWithName("X")
    y = valobj.GetChildMemberWithName("Y")
    z = valobj.GetChildMemberWithName("Z")
    w = valobj.GetChildMemberWithName("W")
    if not all(m.IsValid() for m in [x, y, z, w]):
        return "<unavailable>"
    return "{{X={}, Y={}, Z={}, W={}}}".format(
        x.GetValue() or "?",
        y.GetValue() or "?",
        z.GetValue() or "?",
        w.GetValue() or "?",
    )


def TQuat_summary(valobj, internal_dict):
    x = valobj.GetChildMemberWithName("X")
    y = valobj.GetChildMemberWithName("Y")
    z = valobj.GetChildMemberWithName("Z")
    w = valobj.GetChildMemberWithName("W")
    if not all(m.IsValid() for m in [x, y, z, w]):
        return "<unavailable>"
    return "{{X={}, Y={}, Z={}, W={}}}".format(
        x.GetValue() or "?",
        y.GetValue() or "?",
        z.GetValue() or "?",
        w.GetValue() or "?",
    )


def FRotator_summary(valobj, internal_dict):
    pitch = valobj.GetChildMemberWithName("Pitch")
    yaw = valobj.GetChildMemberWithName("Yaw")
    roll = valobj.GetChildMemberWithName("Roll")
    if not all(m.IsValid() for m in [pitch, yaw, roll]):
        return "<unavailable>"
    return "{{P={}, Y={}, R={}}}".format(
        pitch.GetValue() or "?", yaw.GetValue() or "?", roll.GetValue() or "?"
    )


def TTransform_summary(valobj, internal_dict):
    rotation = valobj.GetChildMemberWithName("Rotation")
    translation = valobj.GetChildMemberWithName("Translation")
    scale = valobj.GetChildMemberWithName("Scale3D")

    parts = []
    if translation.IsValid():
        parts.append("T={}".format(TVector_summary(translation, internal_dict)))
    if rotation.IsValid():
        parts.append("R={}".format(TQuat_summary(rotation, internal_dict)))
    if scale.IsValid():
        parts.append("S={}".format(TVector_summary(scale, internal_dict)))

    return "{{{}}}".format(", ".join(parts)) if parts else "<unavailable>"


# --- TFunction ---


def TFunction_summary(valobj, internal_dict):
    storage = valobj.GetChildMemberWithName("Storage")
    if not storage.IsValid():
        return "<empty>"

    callable = storage.GetChildMemberWithName("Callable")
    if callable.IsValid() and callable.GetValueAsUnsigned(0) != 0:
        return "{{bound at 0x{:x}}}".format(callable.GetValueAsUnsigned(0))

    return "<empty>"


# --- TStringView ---


def TStringView_summary(valobj, internal_dict):
    data = valobj.GetChildMemberWithName("DataPtr")
    size = valobj.GetChildMemberWithName("SizeValue")

    if not data.IsValid() or not size.IsValid():
        return "<unavailable>"

    ptr_val = data.GetValueAsUnsigned(0)
    if ptr_val == 0:
        return "<null>"

    length = size.GetValueAsUnsigned(0)
    if length == 0:
        return '""'

    error = lldb.SBError()
    # Read as wide chars (TCHAR = wchar_t on most UE platforms)
    content = data.GetPointeeData(0, min(length, 256))
    if content.IsValid():
        result = []
        for i in range(min(length, 256)):
            ch = content.GetUnsignedInt16(error, i * 2)
            if error.Fail() or ch == 0:
                break
            result.append(chr(ch))
        return '"{}"'.format("".join(result))

    return "{{len={}}}".format(length)


# --- FGameplayTagContainer ---


def FGameplayTagContainer_summary(valobj, internal_dict):
    tags = valobj.GetChildMemberWithName("GameplayTags")
    if not tags.IsValid():
        return "<unavailable>"

    # TArray<FGameplayTag>
    data = tags.GetChildMemberWithName("AllocatorInstance")
    num = tags.GetChildMemberWithName("ArrayNum")

    if not num.IsValid():
        return "<unavailable>"

    count = num.GetValueAsUnsigned(0)
    if count == 0:
        return "{{empty}}"

    return "{{count={}}}".format(count)
