using System;
using System.Runtime.InteropServices;

namespace WindowsDotfiles
{
    public static class DesktopNativeV2
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SystemParametersInfo(uint action, uint parameter, IntPtr value, uint flags);

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern void SHChangeNotify(uint eventId, uint flags, string item1, IntPtr item2);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ShellFileInfo
        {
            public IntPtr Icon;
            public int Index;
            public uint Attributes;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string Type;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SHGetFileInfo(string path, uint attributes, out ShellFileInfo info, uint size, uint flags);

        public static bool ReloadCursors()
        {
            return SystemParametersInfo(0x0057, 0, IntPtr.Zero, 0);
        }

        public static void RefreshIcons()
        {
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
        }

        public static void RefreshItem(string path)
        {
            // SHCNE_UPDATEITEM with a Unicode path, flushed before verification.
            SHChangeNotify(0x00002000, 0x00001005, path, IntPtr.Zero);
        }

        public static string GetIconLocation(string path)
        {
            ShellFileInfo info;
            // SHGFI_ICONLOCATION asks the Shell which icon it actually resolves.
            if (SHGetFileInfo(path, 0, out info, (uint)Marshal.SizeOf(typeof(ShellFileInfo)), 0x00001000) == IntPtr.Zero)
                throw new InvalidOperationException("Windows could not resolve the icon for " + path);
            return info.Name;
        }
    }
}
