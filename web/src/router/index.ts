import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useMandator } from '../composables/useMandator'

const router = createRouter({
    history: createWebHistory(import.meta.env.BASE_URL),
    routes: [
        // Public routes
        {
            path: '/login',
            name: 'login',
            component: () => import('../views/LoginView.vue'),
            meta: { requiresAuth: false },
        },
        {
            path: '/signup',
            name: 'signup',
            component: () => import('../views/SignUpView.vue'),
            meta: { requiresAuth: false },
        },
        {
            path: '/reset-password',
            name: 'reset-password',
            component: () => import('../views/ResetPasswordView.vue'),
            meta: { requiresAuth: false },
        },
        {
            path: '/update-password',
            name: 'update-password',
            component: () => import('../views/UpdatePasswordView.vue'),
            meta: { requiresAuth: false },
        },

        // Protected routes
        {
            path: '/',
            name: 'home',
            component: () => import('../views/HomeView.vue'),
            meta: { requiresAuth: true },
        },
        {
            path: '/profile',
            name: 'profile',
            component: () => import('../views/ProfileView.vue'),
            meta: { requiresAuth: true },
        },
        {
            path: '/admin',
            name: 'admin',
            component: () => import('../views/AdminView.vue'),
            meta: { requiresAuth: true, requiredRole: 'admin' },
        },
    ],
})

router.beforeEach((to) => {
    const { session, loading } = useAuth()
    const { currentRole, isModuleEnabled } = useMandator()

    // While auth is still loading, allow navigation (the app shell handles the loading state)
    if (loading.value) return true

    const isAuthenticated = !!session.value
    const requiresAuth = to.meta.requiresAuth !== false

    // Redirect unauthenticated users to login
    if (requiresAuth && !isAuthenticated) {
        return { name: 'login', query: { redirect: to.fullPath } }
    }

    // Redirect authenticated users away from auth pages
    if (isAuthenticated && to.meta.requiresAuth === false) {
        return { name: 'home' }
    }

    // Module guard
    if (typeof to.meta.module === 'string' && !isModuleEnabled(to.meta.module)) {
        return { name: 'home' }
    }

    // Role guard
    if (typeof to.meta.requiredRole === 'string' && currentRole.value !== to.meta.requiredRole) {
        return { name: 'home' }
    }

    return true
})

export default router
