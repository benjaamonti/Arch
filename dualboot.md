cfdisk /dev/disk

mkfs.fat -F32 /dev/diskp1

mkfs.ext4 /dev/diskp2

mount /dev/diskp2 /mnt

mkdir /mnt/boot

mount /dev/diskp1 /mnt/boot

archinstall
premounted - > /mnt


pacman os-prober

yay grub customizer




cp -r theme /boot/grub/themes


sudo micro /etc/default/grub

DISABLE OS PROBER
GRUB THEME= "/boot/grub/themes/THEME/theme.txt"
