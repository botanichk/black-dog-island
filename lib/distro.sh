# lib/distro.sh - какая система и какой пакетный менеджер.
# Подключается после lib/log.sh.
#
# Семейство берём из /etc/os-release: ID и ID_LIKE. Void и Arch не связаны,
# поэтому проверяем оба поля. Неизвестная система - не ошибка: check
# продолжает работать, а install отказывается ставить пакеты.

BDI_DISTRO=""
BDI_PKGMGR=""
BDI_DEPS=""

distro_detect() {
  BDI_DISTRO=unknown
  BDI_PKGMGR=""
  BDI_DEPS=""

  # OS_RELEASE - только для тестов: на живой системе файла нет в окружении.
  _os=${OS_RELEASE:-/etc/os-release}
  [ -r "$_os" ] || return 0
  # Без `.` и eval: os-release - чужой файл, значения берём как текст.
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

# Команда установки пакетов. Печатает одну строку, ничего не запускает.
distro_install_cmd() {
  case "$BDI_PKGMGR" in
    pacman) printf 'sudo pacman -S --needed --noconfirm %s\n' "$*" ;;
    xbps-install) printf 'sudo xbps-install -S %s\n' "$*" ;;
    *) printf '' ;;
  esac
}

# Проверка, стоит ли пакет. 0 - стоит. Для неизвестной системы считаем,
# что проверить нельзя (код 2), чтобы не врать "не стоит".
distro_has_pkg() {
  case "$BDI_PKGMGR" in
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    xbps-install) xbps-query "$1" >/dev/null 2>&1 ;;
    *) return 2 ;;
  esac
}
