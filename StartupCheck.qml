import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("voxtypeCheck", ["which", "voxtype"], (stdout, exitCode) => {
            if (exitCode === 0) {
                Proc.runCommand("voxtypeCavaCheck", ["which", "cava"], (stdout2, exitCode2) => {
                    if (exitCode2 === 0) {
                        done(null)
                        return
                    }
                    done({
                        title: I18n.tr("cava is required"),
                        details: I18n.tr("Install cava with your package manager (e.g. `pacman -S cava` or `dnf install cava`).")
                    })
                })
                return
            }
            done({
                title: I18n.tr("voxtype is required"),
                details: I18n.tr("Install voxtype (e.g. `paru -S voxtype-bin` or see https://voxtype.io).")
            })
        })
    }
}
