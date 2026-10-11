package nl.mennovanhout.nspanel_app

/** Keeps Android's idle timer out of the app's display policy, without waking it.
 * Repeated screen/lifecycle/configuration events must not stack acquisitions.
 */
class DisplayAwakeHold(private val acquire: () -> Unit, private val release: () -> Unit) {
    private var held = false

    fun update(owned: Boolean, foreground: Boolean, interactive: Boolean) {
        val needed = owned && foreground && interactive
        if (needed == held) return
        if (needed) acquire() else release()
        held = needed
    }
}
