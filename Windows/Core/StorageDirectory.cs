using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;
using static Kornucopia.Core.BoardStore;

namespace Kornucopia.Core;

// Every operation keeps its verified ancestry and root open. Child names are
// single components, resolved relative to this root, never reopened by pathname.
internal sealed class StorageDirectory : IDisposable
{
    readonly List<SafeFileHandle> handles = [];
    readonly List<string> components = [];
    SafeFileHandle Root => handles[^1];
    string? finalRoot;
    static string? installerSid;
    public string Identity => Metadata(Root).Identity;
    static StorageException Unsafe() => new("error.storageUnsafeRoot");
    static StorageException Changed() => new("error.storageChanged");

    public static StorageDirectory Open(string path, bool create)
    {
        var operation = new StorageDirectory();
        try { operation.OpenComponents(path, create); return operation; }
        catch { operation.Dispose(); throw; }
    }
    void OpenComponents(string path, bool create)
    {
        if (OperatingSystem.IsWindows()) { OpenWindowsComponents(path, create); return; }
        // These system-owned aliases are part of macOS's normal temporary paths.
        // No configured/user-controlled component is canonicalized through a link.
        if (OperatingSystem.IsMacOS())
        {
            foreach (var alias in new[] { "/var", "/tmp", "/etc" })
                if (path.StartsWith(alias + "/", StringComparison.Ordinal))
                {
                    VerifySystemAlias(alias); path = "/private" + path; break;
                }
        }
        var parts = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) throw Unsafe();
        var initial = Native.Open("/", DirectoryFlags);
        if (initial < 0) throw Unsafe();
        handles.Add(new SafeFileHandle(new IntPtr(initial), true));
        CheckUnixAncestor(Root);
        for (var i = 0; i < parts.Length; i++)
        {
            Component(parts[i]);
            var fd = Native.OpenAt(Root.DangerousGetHandle().ToInt32(), parts[i], DirectoryFlags, 0);
            if (fd < 0 && Marshal.GetLastPInvokeError() == 2)
            {
                if (!create) throw Changed();
                if (Native.MkdirAt(Root.DangerousGetHandle().ToInt32(), parts[i], 0x1c0) != 0) throw Changed();
                fd = Native.OpenAt(Root.DangerousGetHandle().ToInt32(), parts[i], DirectoryFlags, 0);
            }
            if (fd < 0) throw Unsafe();
            handles.Add(new SafeFileHandle(new IntPtr(fd), true)); components.Add(parts[i]);
            if (Metadata(Root).Kind != EntryKind.Directory) throw Unsafe();
            if (i < parts.Length - 1) CheckUnixAncestor(Root);
        }
        CheckPrivateRoot(); Verify();
    }
    static void VerifySystemAlias(string alias)
    {
        var buffer = Marshal.AllocHGlobal(512);
        try
        {
            if (Native.LStat(alias, buffer) != 0 || (uint)Marshal.ReadInt32(buffer, 16) != 0) throw Unsafe();
            var bytes = new byte[256]; var count = Native.ReadLink(alias, bytes, (UIntPtr)bytes.Length).ToInt64();
            if (count <= 0) throw Unsafe();
            var target = Encoding.UTF8.GetString(bytes, 0, (int)count);
            if (target != "/private" + alias && target != "private" + alias) throw Unsafe();
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    [SupportedOSPlatform("windows")]
    void OpenWindowsComponents(string path, bool create)
    {
        // Network shares and device namespaces are not private local storage.
        var volume = Path.GetPathRoot(path);
        if (volume is null || volume.Length != 3 || volume[1] != ':' || !char.IsAsciiLetter(volume[0])) throw Unsafe();
        var initial = Native.CreateFile(volume, 0x1200a0, 3, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
        if (initial.IsInvalid) { initial.Dispose(); throw Unsafe(); }
        handles.Add(initial);
        if (Metadata(initial).Kind != EntryKind.Directory) throw Unsafe();
        CheckWindowsAcl(initial, false);
        var parts = path[volume.Length..].Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) throw Unsafe();
        foreach (var part in parts)
        {
            Component(part);
            var opened = NtOpen(Root, part, 0x1200a0, 3, 1, 0x00200021, true, false);
            if (opened is null)
            {
                if (!create) throw Changed();
                opened = NtOpen(Root, part, 0x1200a0, 3, 2, 0x00200021, true, true) ?? throw Changed();
            }
            handles.Add(opened); components.Add(part);
            if (Metadata(opened).Kind != EntryKind.Directory) throw Unsafe();
            CheckWindowsAcl(opened, false);
        }
        finalRoot = FinalPath(Root).TrimEnd('\\');
        CheckPrivateRoot(); Verify();
    }
    public void Verify()
    {
        for (var i = 0; i < components.Count; i++)
        {
            var current = InspectAt(handles[i], components[i]);
            if (current is null || current.Value.Kind != EntryKind.Directory || current.Value.Identity != Metadata(handles[i + 1]).Identity) throw Changed();
        }
        CheckPrivateRoot();
    }
    void CheckPrivateRoot()
    {
        if (OperatingSystem.IsWindows()) { CheckWindowsAcl(Root); return; }
        CheckUnixAccess(Root, true);
    }
    static void CheckUnixAccess(SafeFileHandle handle, bool privateRoot)
    {
        var buffer = Marshal.AllocHGlobal(512);
        try
        {
            if (Native.FStat(handle.DangerousGetHandle().ToInt32(), buffer) != 0) throw Unsafe();
            var mac = OperatingSystem.IsMacOS(); var arm = RuntimeInformation.ProcessArchitecture == Architecture.Arm64;
            var mode = mac ? (ushort)Marshal.ReadInt16(buffer, 4) : Marshal.ReadInt32(buffer, arm ? 16 : 24);
            var owner = (uint)Marshal.ReadInt32(buffer, mac ? 16 : arm ? 24 : 28);
            if (owner != Native.GetEUid() || (mode & (privateRoot ? 0x3f : 0x12)) != 0) throw Unsafe();
            // Extended ACLs can grant access even when the mode is 0700.
            if (mac)
            {
                var acl = Native.AclGetFd(handle.DangerousGetHandle().ToInt32(), 0x100);
                if (acl == IntPtr.Zero) { if (Marshal.GetLastPInvokeError() != 2) throw Unsafe(); }
                else
                {
                    try
                    {
                        if (Native.AclGetEntry(acl, 0, out _) == 0 || Marshal.GetLastPInvokeError() != 22) throw Unsafe();
                    }
                    finally { Native.AclFree(acl); }
                }
            }
            else
            {
                var aclSize = Native.GetXAttr(handle.DangerousGetHandle().ToInt32(), "system.posix_acl_access", IntPtr.Zero, UIntPtr.Zero);
                if (aclSize.ToInt64() >= 0) throw Unsafe();
                var error = Marshal.GetLastPInvokeError();
                if (error is not (61 or 95)) throw Unsafe(); // ENODATA / ENOTSUP.
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    static void CheckUnixAncestor(SafeFileHandle handle)
    {
        var buffer = Marshal.AllocHGlobal(512);
        try
        {
            if (Native.FStat(handle.DangerousGetHandle().ToInt32(), buffer) != 0) throw Unsafe();
            var mac = OperatingSystem.IsMacOS(); var arm = RuntimeInformation.ProcessArchitecture == Architecture.Arm64;
            var mode = mac ? (ushort)Marshal.ReadInt16(buffer, 4) : Marshal.ReadInt32(buffer, arm ? 16 : 24);
            var owner = (uint)Marshal.ReadInt32(buffer, mac ? 16 : arm ? 24 : 28);
            if (owner != 0 && owner != Native.GetEUid()) throw Unsafe();
            // A system-owned sticky temporary directory permits creating peers,
            // while preventing a foreign account from replacing our component.
            if ((mode & 0x12) != 0 && !(owner == 0 && (mode & 0x200) != 0)) throw Unsafe();
            if (mac)
            {
                var acl = Native.AclGetFd(handle.DangerousGetHandle().ToInt32(), 0x100);
                if (acl == IntPtr.Zero) { if (Marshal.GetLastPInvokeError() != 2) throw Unsafe(); }
                else
                {
                    try
                    {
                        var entryId = 0;
                        while (Native.AclGetEntry(acl, entryId, out var entry) == 0)
                        {
                            if (Native.AclGetTag(entry, out var tag) != 0 || tag != 2) throw Unsafe();
                            entryId = -1;
                        }
                        if (Marshal.GetLastPInvokeError() != 22) throw Unsafe();
                    }
                    finally { Native.AclFree(acl); }
                }
            }
            else
            {
                if (Native.GetXAttr(handle.DangerousGetHandle().ToInt32(), "system.posix_acl_access", IntPtr.Zero, UIntPtr.Zero).ToInt64() >= 0) throw Unsafe();
                if (Marshal.GetLastPInvokeError() is not (61 or 95)) throw Unsafe();
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    [SupportedOSPlatform("windows")]
    static void CheckWindowsAcl(SafeFileHandle handle, bool privateStorage = true)
    {
        var error = Native.GetSecurityInfo(handle, 1, 5, out var owner, out _, out var dacl, out _, out var descriptor);
        if (error != 0 || descriptor == IntPtr.Zero) throw Unsafe();
        try
        {
            using var token = WindowsIdentity.GetCurrent();
            var current = token.User?.Value ?? throw Unsafe();
            var trusted = new List<string> { current, "S-1-5-18", "S-1-5-32-544" };
            if (!privateStorage)
            {
                try
                {
                    // Fixed Windows servicing identity, allowed only on ancestors.
                    installerSid ??= ((SecurityIdentifier)new NTAccount("NT SERVICE", "TrustedInstaller").Translate(typeof(SecurityIdentifier))).Value;
                    trusted.Add(installerSid);
                }
                catch (IdentityNotMappedException) { throw Unsafe(); }
            }
            if (owner == IntPtr.Zero || dacl == IntPtr.Zero) throw Unsafe();
            var ownerSid = new SecurityIdentifier(owner).Value;
            var trustedOwner = trusted.Contains(ownerSid);
            if (!trustedOwner) throw Unsafe();
            var size = Native.GetSecurityDescriptorLength(descriptor);
            if (size == 0 || size > 65536) throw Unsafe();
            var bytes = new byte[size]; Marshal.Copy(descriptor, bytes, 0, bytes.Length);
            var security = new RawSecurityDescriptor(bytes, 0);
            if (security.DiscretionaryAcl is null) throw Unsafe();
            foreach (GenericAce ace in security.DiscretionaryAcl)
            {
                if (ace is not QualifiedAce qualified) throw Unsafe();
                if (qualified.AceQualifier != AceQualifier.AccessAllowed || (ace.AceFlags & AceFlags.InheritOnly) != 0) continue;
                var dangerous = privateStorage ? qualified.AccessMask != 0 : ((uint)qualified.AccessMask & 0x500d0040u) != 0;
                // On ancestors, creating a sibling is harmless. Deleting or
                // taking control of an existing component is refused.
                if (!trusted.Contains(qualified.SecurityIdentifier.Value) && dangerous) throw Unsafe();
            }
        }
        finally { Native.LocalFree(descriptor); }
    }
    public EntryMetadata? Inspect(string name) { Component(name); Verify(); return InspectAt(Root, name); }
    EntryMetadata? InspectAt(SafeFileHandle directory, string name)
    {
        if (OperatingSystem.IsWindows())
        {
            using var handle = NtOpen(directory, name, 0x100080, 7, 1, 0x00200020, false, false);
            return handle is null ? null : Metadata(handle);
        }
        var buffer = Marshal.AllocHGlobal(512);
        try
        {
            if (Native.FStatAt(directory.DangerousGetHandle().ToInt32(), name, buffer, OperatingSystem.IsMacOS() ? 0x20 : 0x100) != 0)
            {
                if (Marshal.GetLastPInvokeError() is 2 or 20) return null;
                throw new IOException("Unable to inspect the reserved file.");
            }
            return UnixMetadata(buffer);
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    public byte[] Read(string name, EntryMetadata expected, int maximum = BoardBudget.FileBytes)
    {
        Component(name); Verify();
        if (expected.Kind != EntryKind.Regular || expected.Links != 1) throw new StorageException("error.storageFileType");
        using var handle = OpenLeaf(name, false);
        if (handle is null || Metadata(handle) != expected) throw Changed();
        CheckLeaf(handle, name);
        // The original handle remains valid for metadata checks after stream disposal.
        using var borrowed = new SafeFileHandle(handle.DangerousGetHandle(), false);
        using var stream = new FileStream(borrowed, FileAccess.Read, 65536, false);
        var length = stream.Length;
        if (length > maximum || length < 0) throw new StorageException("error.storageFileSize");
        var bytes = new byte[(int)length]; var offset = 0;
        while (offset < bytes.Length)
        {
            var count = stream.Read(bytes, offset, bytes.Length - offset);
            if (count == 0) throw Changed(); offset += count;
        }
        if (stream.ReadByte() != -1) throw new StorageException("error.storageFileSize");
        if (Metadata(handle) != expected) throw Changed();
        Verify(); return bytes;
    }
    SafeFileHandle? OpenLeaf(string name, bool deleting)
    {
        if (OperatingSystem.IsWindows()) return NtOpen(Root, name, deleting ? 0x130080u : 0x120089u, deleting ? 3u : 1u, 1, 0x00200020, false, false);
        var fd = Native.OpenAt(Root.DangerousGetHandle().ToInt32(), name, NoFollow | NonBlock | CloseExec, 0);
        if (fd < 0) throw Changed();
        return new SafeFileHandle(new IntPtr(fd), true);
    }
    void CheckLeaf(SafeFileHandle handle, string name)
    {
        var metadata = Metadata(handle);
        if (metadata.Kind != EntryKind.Regular || metadata.Links != 1) throw new StorageException("error.storageFileType");
        if (OperatingSystem.IsWindows())
        {
            if (!FinalPath(handle).Equals(finalRoot + "\\" + name, StringComparison.OrdinalIgnoreCase)) throw Changed();
            CheckWindowsAcl(handle);
        }
        else CheckUnixAccess(handle, false);
    }
    public void Preserve(string name, EntryMetadata expected, bool preferences = false)
    {
        Component(name); Verify();
        if (expected.Kind is not (EntryKind.Regular or EntryKind.Link)) throw new StorageException("error.storageFileType");
        if (InspectAt(Root, name) != expected) throw Changed();
        var destination = preferences ? name + ".corrupt-" + Guid.NewGuid().ToString("N") : Path.GetFileNameWithoutExtension(name) + ".corrupt-" + Guid.NewGuid().ToString("N") + ".json";
        if (OperatingSystem.IsWindows())
        {
            using var handle = OpenLeaf(name, true);
            if (handle is null || Metadata(handle) != expected) throw Changed();
            // Reparse entries and hard links stay un-followed. Pin their own
            // entry against deletion and check confinement before its rename.
            if (!FinalPath(handle).Equals(finalRoot + "\\" + name, StringComparison.OrdinalIgnoreCase)) throw Changed();
            Rename(handle, destination, false);
        }
        else RenameUnix(name, destination, false);
    }
    public void Write(string name, byte[] bytes, EntryMetadata? expected)
    {
        Component(name); Verify();
        var temporary = name + ".tmp-" + Guid.NewGuid().ToString("N");
        using var handle = CreateTemporary(temporary);
        var renamed = false;
        try
        {
            CheckLeaf(handle, temporary);
            using (var borrowed = new SafeFileHandle(handle.DangerousGetHandle(), false))
            using (var stream = new FileStream(borrowed, FileAccess.Write, 65536, false)) { stream.Write(bytes); stream.Flush(true); }
            Verify();
            if (InspectAt(Root, name) != expected) throw Changed();
            if (OperatingSystem.IsWindows()) Rename(handle, name, expected is not null);
            else RenameUnix(temporary, name, expected is not null);
            renamed = true;
        }
        finally
        {
            // Cleanup is relative to the original directory, even after a root swap.
            if (!renamed)
            {
                if (OperatingSystem.IsWindows()) { try { Delete(handle); } catch (IOException) { } }
                else Native.UnlinkAt(Root.DangerousGetHandle().ToInt32(), temporary, 0);
            }
        }
    }
    SafeFileHandle CreateTemporary(string name)
    {
        if (OperatingSystem.IsWindows()) return NtOpen(Root, name, 0x13019f, 0, 2, 0x00200060, true, true) ?? throw Changed();
        var flags = 2 | Create | Exclusive | NoFollow | CloseExec;
        // Darwin ARM64 passes C variadic arguments on the stack, after the eight
        // argument registers. The mode is variadic in openat, unlike mkdirat.
        var fd = OperatingSystem.IsMacOS() && RuntimeInformation.ProcessArchitecture == Architecture.Arm64
            ? Native.OpenAtMacCreate(Root.DangerousGetHandle().ToInt32(), name, flags, 0, 0, 0, 0, 0, 0x180)
            : Native.OpenAt(Root.DangerousGetHandle().ToInt32(), name, flags, 0x180);
        if (fd < 0) throw new IOException("Unable to create the private temporary file.");
        return new SafeFileHandle(new IntPtr(fd), true);
    }
    void RenameUnix(string source, string destination, bool replace)
    {
        var fd = Root.DangerousGetHandle().ToInt32();
        var result = replace ? Native.RenameAt(fd, source, fd, destination) : OperatingSystem.IsMacOS() ? Native.RenameAtExclusiveMac(fd, source, fd, destination, 4) : Native.RenameAtExclusiveLinux(fd, source, fd, destination, 1);
        if (result != 0) throw Changed();
    }
    void Rename(SafeFileHandle handle, string destination, bool replace)
    {
        var encoded = Encoding.Unicode.GetBytes(destination);
        var buffer = Marshal.AllocHGlobal(24 + encoded.Length);
        try
        {
            for (var i = 0; i < 24 + encoded.Length; i++) Marshal.WriteByte(buffer, i, 0);
            Marshal.WriteByte(buffer, replace ? (byte)1 : (byte)0);
            Marshal.WriteIntPtr(buffer, 8, Root.DangerousGetHandle()); Marshal.WriteInt32(buffer, 16, encoded.Length);
            Marshal.Copy(encoded, 0, buffer + 20, encoded.Length);
            if (Native.NtSetInformationFile(handle, out _, buffer, (uint)(24 + encoded.Length), 10) < 0) throw Changed();
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    static void Delete(SafeFileHandle handle)
    {
        var buffer = Marshal.AllocHGlobal(1);
        try { Marshal.WriteByte(buffer, 1); if (Native.NtSetInformationFile(handle, out _, buffer, 1, 13) < 0) throw new IOException("Unable to remove the temporary file."); }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    [SupportedOSPlatform("windows")]
    static SafeFileHandle? NtOpen(SafeFileHandle parent, string name, uint access, uint share, uint disposition, uint options, bool rejectReparse, bool privateSecurity)
    {
        var text = Marshal.StringToHGlobalUni(name); var unicode = Marshal.AllocHGlobal(Marshal.SizeOf<Native.UnicodeString>());
        IntPtr security = IntPtr.Zero;
        try
        {
            var length = checked((ushort)(name.Length * 2));
            Marshal.StructureToPtr(new Native.UnicodeString { Length = length, MaximumLength = length, Buffer = text }, unicode, false);
            if (privateSecurity)
            {
                using var token = WindowsIdentity.GetCurrent();
                var user = token.User?.Value ?? throw Unsafe();
                var sddl = "O:" + user + "G:" + user + "D:P(A;OICI;FA;;;" + user + ")(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";
                if (!Native.ConvertSecurityDescriptor(sddl, 1, out security, out _)) throw Unsafe();
            }
            var attributes = new Native.ObjectAttributes { Length = (uint)Marshal.SizeOf<Native.ObjectAttributes>(), RootDirectory = parent.DangerousGetHandle(), ObjectName = unicode, Attributes = 0x40u | (rejectReparse ? 0x1000u : 0), SecurityDescriptor = security };
            var status = Native.NtCreateFile(out var raw, access, ref attributes, out _, IntPtr.Zero, 0x80, share, disposition, options, IntPtr.Zero, 0);
            if (status >= 0) return new SafeFileHandle(raw, true);
            if (raw != IntPtr.Zero && raw != new IntPtr(-1)) new SafeFileHandle(raw, true).Dispose();
            if (status is unchecked((int)0xc0000034) or unchecked((int)0xc000003a)) return null;
            if (rejectReparse) throw Unsafe();
            throw new IOException("Unable to open the reserved file safely.", new Win32Exception((int)Native.RtlNtStatusToDosError(status)));
        }
        finally { if (security != IntPtr.Zero) Native.LocalFree(security); Marshal.FreeHGlobal(unicode); Marshal.FreeHGlobal(text); }
    }
    static string FinalPath(SafeFileHandle handle)
    {
        var text = new StringBuilder(32768); var length = Native.GetFinalPath(handle, text, (uint)text.Capacity, 0);
        if (length == 0 || length >= text.Capacity) throw Changed(); return text.ToString();
    }
    static void Component(string name)
    {
        if (name.Length == 0 || name.Length > 255 || name is "." or ".." || name.IndexOfAny(['/', '\\', ':', '\0']) >= 0 || name.EndsWith(' ') || name.EndsWith('.')) throw Unsafe();
    }
    static int NoFollow => OperatingSystem.IsMacOS() ? 0x100 : 0x20000;
    static int NonBlock => OperatingSystem.IsMacOS() ? 4 : 0x800;
    static int CloseExec => OperatingSystem.IsMacOS() ? 0x1000000 : 0x80000;
    static int Create => OperatingSystem.IsMacOS() ? 0x200 : 0x40;
    static int Exclusive => OperatingSystem.IsMacOS() ? 0x800 : 0x80;
    static int DirectoryFlags => NoFollow | CloseExec | (OperatingSystem.IsMacOS() ? 0x100000 : 0x10000);
    public void Dispose() { for (var i = handles.Count - 1; i >= 0; i--) handles[i].Dispose(); handles.Clear(); }
    static class Native
    {
        [StructLayout(LayoutKind.Sequential)] public struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
        [StructLayout(LayoutKind.Sequential)] public struct ObjectAttributes { public uint Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
        [StructLayout(LayoutKind.Sequential)] public struct IoStatus { public IntPtr Status; public UIntPtr Information; }
        [DllImport("ntdll.dll")] public static extern int NtCreateFile(out IntPtr handle, uint access, ref ObjectAttributes attributes, out IoStatus status, IntPtr size, uint fileAttributes, uint share, uint disposition, uint options, IntPtr ea, uint eaLength);
        [DllImport("ntdll.dll")] public static extern int NtSetInformationFile(SafeFileHandle handle, out IoStatus status, IntPtr data, uint length, uint informationClass);
        [DllImport("ntdll.dll")] public static extern uint RtlNtStatusToDosError(int status);
        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)] public static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", CharSet = CharSet.Unicode, SetLastError = true)] public static extern uint GetFinalPath(SafeFileHandle handle, StringBuilder text, uint length, uint flags);
        [DllImport("advapi32.dll")] public static extern uint GetSecurityInfo(SafeFileHandle handle, uint type, uint information, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);
        [DllImport("advapi32.dll")] public static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
        [DllImport("advapi32.dll", EntryPoint = "ConvertStringSecurityDescriptorToSecurityDescriptorW", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool ConvertSecurityDescriptor(string sddl, uint revision, out IntPtr descriptor, out uint size);
        [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("libc", EntryPoint = "open", SetLastError = true)] public static extern int Open(string path, int flags);
        [DllImport("libc", EntryPoint = "openat", SetLastError = true)] public static extern int OpenAt(int directory, string name, int flags, uint mode);
        [DllImport("libc", EntryPoint = "openat", SetLastError = true)] public static extern int OpenAtMacCreate(int directory, string name, int flags, long pad1, long pad2, long pad3, long pad4, long pad5, uint mode);
        [DllImport("libc", EntryPoint = "mkdirat", SetLastError = true)] public static extern int MkdirAt(int directory, string name, uint mode);
        [DllImport("libc", EntryPoint = "fstat", SetLastError = true)] public static extern int FStat(int descriptor, IntPtr buffer);
        [DllImport("libc", EntryPoint = "lstat", SetLastError = true)] public static extern int LStat(string path, IntPtr buffer);
        [DllImport("libc", EntryPoint = "fstatat", SetLastError = true)] public static extern int FStatAt(int directory, string name, IntPtr buffer, int flags);
        [DllImport("libc", EntryPoint = "readlink", SetLastError = true)] public static extern IntPtr ReadLink(string path, byte[] text, UIntPtr length);
        [DllImport("libc", EntryPoint = "geteuid")] public static extern uint GetEUid();
        [DllImport("libc", EntryPoint = "acl_get_fd_np", SetLastError = true)] public static extern IntPtr AclGetFd(int descriptor, int type);
        [DllImport("libc", EntryPoint = "acl_get_entry", SetLastError = true)] public static extern int AclGetEntry(IntPtr acl, int entryId, out IntPtr entry);
        [DllImport("libc", EntryPoint = "acl_get_tag_type", SetLastError = true)] public static extern int AclGetTag(IntPtr entry, out uint tag);
        [DllImport("libc", EntryPoint = "acl_free")] public static extern int AclFree(IntPtr acl);
        [DllImport("libc", EntryPoint = "fgetxattr", SetLastError = true)] public static extern IntPtr GetXAttr(int descriptor, string name, IntPtr value, UIntPtr size);
        [DllImport("libc", EntryPoint = "renameat", SetLastError = true)] public static extern int RenameAt(int oldDirectory, string oldName, int newDirectory, string newName);
        [DllImport("libc", EntryPoint = "renameatx_np", SetLastError = true)] public static extern int RenameAtExclusiveMac(int oldDirectory, string oldName, int newDirectory, string newName, uint flags);
        [DllImport("libc", EntryPoint = "renameat2", SetLastError = true)] public static extern int RenameAtExclusiveLinux(int oldDirectory, string oldName, int newDirectory, string newName, uint flags);
        [DllImport("libc", EntryPoint = "unlinkat", SetLastError = true)] public static extern int UnlinkAt(int directory, string name, int flags);
    }
}
