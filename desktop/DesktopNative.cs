using System;
using System.Runtime.InteropServices;

namespace WindowsDotfiles
{
    public static class DesktopNative
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SystemParametersInfo(uint action, uint parameter, IntPtr value, uint flags);

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);

        public static bool ReloadCursors()
        {
            return SystemParametersInfo(0x0057, 0, IntPtr.Zero, 0);
        }

        public static void RefreshIcons()
        {
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
