import { ref } from 'vue'
import type { User, Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'

const user = ref<User | null>(null)
const session = ref<Session | null>(null)
const loading = ref(true)
let initialised = false

function init() {
    if (initialised) return
    initialised = true

    supabase.auth.getSession().then(({ data }) => {
        session.value = data.session
        user.value = data.session?.user ?? null
        loading.value = false
    })

    supabase.auth.onAuthStateChange((_event, s) => {
        session.value = s
        user.value = s?.user ?? null
    })
}

export function useAuth() {
    init()

    async function signIn(email: string, password: string) {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
    }

    async function signUp(email: string, password: string) {
        const { error } = await supabase.auth.signUp({ email, password })
        if (error) throw error
    }

    async function signOut() {
        const { error } = await supabase.auth.signOut()
        if (error) throw error
    }

    async function resetPassword(email: string) {
        const { error } = await supabase.auth.resetPasswordForEmail(email, {
            redirectTo: `${window.location.origin}/update-password`,
        })
        if (error) throw error
    }

    async function updatePassword(newPassword: string) {
        const { error } = await supabase.auth.updateUser({ password: newPassword })
        if (error) throw error
    }

    return {
        user,
        session,
        loading,
        signIn,
        signUp,
        signOut,
        resetPassword,
        updatePassword,
    }
}
