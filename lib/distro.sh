# lib/distro.sh - какая система и какой пакетный менеджер.
# Подключается после lib/log.sh.
#
# Поддержаны две системы: Arch (pacman) и Void (xbps). Семейство берём из
# /etc/os-release: ID и ID_LIKE, потому что CachyOS/Manjaro пишут "arch" в
# ID_LIKE, а не в ID. Неизвестная система - не ошибка: check продолжает
# работать и проверяет команды, а install отказывается ставить пакеты.

BDI_DISTRO=""
BDI_PKGMGR=""
BDI_DEPS=""

distro_detect() {
  BDI_DISTRO=unknown
  BDI_PKGMGR=""
  BDI_DEPS=""

  # OS_RELEASE - только для тестов: на живой системе этой переменной нет.
  _os=${OS_RELEASE:-/etc/os-release}
  [ -r "$_os" ] || return 0
  # Без `.` и eval: os-release чужой файл, значения берём как текст.
  _id=$(sed -n 's/^ID=//p' "$_os" | tr -d '"' | head -1)
  _like=$(sed -n 's/^ID_LIKE=//p' "$_os" | tr -d '"' | head -1)

  case "$_id" in
    cachyos|arch|archarm|endeavouros|manjaro) BDI_DISTRO=arch ;;
    void) BDI_DISTRO=void ;;
    *)
      case " $_like " in
        *arch*) BDI_DISTRO=arch ;;
        *void*) BDI_DISTRO=void ;;
      esac ;;
  esac

  case "$BDI_DISTRO" in
    arch) BDI_PKGMGR=pacman; BDI_DEPS=arch.txt ;;
    void) BDI_PKGMGR=xbps-install; BDI_DEPS=void.txt ;;
  esac
}

# Печатает одну строку команды установки, ничего не запускает.
# Аргументы - имена пакетов.
distro_install_cmd() {
  case "$BDI_PKGMGR" in
    pacman) printf 'sudo pacman -S --needed %s\n' "$*" ;;
    xbps-install) printf 'sudo xbps-install -S %s\n' "$*" ;;
    *) printf '' ;;
  esac
}
