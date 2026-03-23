import { ref, onMounted, onUnmounted } from 'vue'

const MOBILE_BREAKPOINT = '(max-width: 600px)'

export function useIsMobile() {
    const isMobile = ref(false)
    let mql: MediaQueryList | null = null

    function onMediaChange(e: MediaQueryListEvent | MediaQueryList) {
        isMobile.value = e.matches
    }

    onMounted(() => {
        mql = window.matchMedia(MOBILE_BREAKPOINT)
        onMediaChange(mql)
        mql.addEventListener('change', onMediaChange)
    })

    onUnmounted(() => {
        mql?.removeEventListener('change', onMediaChange)
    })

    return isMobile
}
