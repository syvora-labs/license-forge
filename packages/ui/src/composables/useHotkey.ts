import { onMounted, onUnmounted } from 'vue'

export function useHotkey(key: string, callback: () => void) {
    function handler(e: KeyboardEvent) {
        if (e.key.toLowerCase() !== key.toLowerCase()) return
        if (!(e.metaKey || e.ctrlKey)) return
        e.preventDefault()
        callback()
    }

    onMounted(() => window.addEventListener('keydown', handler))
    onUnmounted(() => window.removeEventListener('keydown', handler))
}
