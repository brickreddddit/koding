// Imported from https://github.com/bazil/fuse.
package fs

import (
	"regexp"
	"syscall"
)

var re = regexp.MustCompile(`\\(.)`)

// unescape removes backslash-escaping. The escaped characters are not
// mapped in any way; that is, unescape(`\n` ) == `n`.
func unescape(s string) string {
	return re.ReplaceAllString(s, `$1`)
}

func getMountInfo(mnt string) (*MountInfo, error) {
	var st syscall.Statfs_t
	err := syscall.Statfs(mnt, &st)
	if err != nil {
		return nil, err
	}
	i := &MountInfo{
		FSName: unescape(cstr(st.Mntfromname[:])),
	}
	return i, nil
}
