# نصب MikroTik CHR روی Ubuntu

این مخزن شامل یک اسکریپت آماده برای نصب و ساخت ماشین مجازی MikroTik CHR روی سرور Ubuntu است.

## فایل‌ها

- `install-mikrotik-chr.sh`: اسکریپت اصلی نصب

## پیش‌نیازها

- Ubuntu Server (ترجیحاً 22.04 یا جدیدتر)
- دسترسی `root` یا `sudo`
- فعال بودن virtualization (VT-x/AMD-V)
- داشتن Linux bridge (مثل `br0`) روی سرور

## استفاده سریع

```bash
sudo ./install-mikrotik-chr.sh --bridge br0
```

## نمونه با تنظیمات سفارشی

```bash
sudo ./install-mikrotik-chr.sh \
  --bridge br0 \
  --vm-name chr-office \
  --ram 1024 \
  --vcpus 2 \
  --disk-size 4 \
  --chr-version 7.16.2
```

## پارامترها

- `--bridge`: نام bridge (اجباری)
- `--vm-name`: نام VM (پیش‌فرض: `mikrotik-chr`)
- `--ram`: مقدار RAM به MB (پیش‌فرض: `512`)
- `--vcpus`: تعداد CPU (پیش‌فرض: `1`)
- `--disk-size`: اندازه دیسک به GB (پیش‌فرض: `2`)
- `--chr-version`: نسخه CHR (پیش‌فرض: `7.16.2`)
- `--workdir`: مسیر فایل‌های image (پیش‌فرض: `/var/lib/libvirt/images`)
- `--no-autostart`: غیرفعال کردن autostart VM

## نکته

بعد از ساخته شدن VM برای اتصال کنسول:

```bash
virsh console mikrotik-chr
```

ورود اولیه MikroTik:

- user: `admin`
- password: خالی
