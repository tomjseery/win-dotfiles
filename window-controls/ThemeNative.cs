using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WindowsDotfiles
{
    public static class ThemeNativeV1
    {
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        private static extern int GetCurrentThemeName(StringBuilder path, int pathSize,
            StringBuilder color, int colorSize, StringBuilder size, int sizeSize);

        [DllImport("uxtheme.dll", EntryPoint = "#65", CharSet = CharSet.Unicode)]
        private static extern int SetSystemVisualStyle(string path, string color, string size, int reserved);

        public static string[] Current()
        {
            var path = new StringBuilder(32768);
            var color = new StringBuilder(256);
            var size = new StringBuilder(256);
            Marshal.ThrowExceptionForHR(GetCurrentThemeName(path, path.Capacity, color, color.Capacity, size, size.Capacity));
            return new[] { path.ToString(), color.ToString(), size.ToString() };
        }

        public static void Apply(string path, string color, string size)
        {
            Marshal.ThrowExceptionForHR(SetSystemVisualStyle(path, color, size, 0));
            var current = Current();
            if (!string.Equals(current[0], path, StringComparison.OrdinalIgnoreCase)
                || current[1] != color || current[2] != size)
                throw new InvalidOperationException("Windows did not activate the requested visual style.");
        }
    }
}
