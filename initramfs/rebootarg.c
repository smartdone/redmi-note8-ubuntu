/* rebootarg MODE: reboot with an argument (e.g. "recovery", "bootloader").
 * busybox reboot cannot pass one; the PMIC PON driver stores it for the bootloader. */
#include <linux/reboot.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	sync();
	return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		       LINUX_REBOOT_CMD_RESTART2, argc > 1 ? argv[1] : "");
}
