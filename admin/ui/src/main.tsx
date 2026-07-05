import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { routeTree } from './routeTree.gen'
import { applyBrand } from './brand'
import { ShellSession } from './components/ShellSession'
import './index.css'

applyBrand()

const router = createRouter({ routeTree })

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={router} />
    <ShellSession router={router} />
  </StrictMode>
)
