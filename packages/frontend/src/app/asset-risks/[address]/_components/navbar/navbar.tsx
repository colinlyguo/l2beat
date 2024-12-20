import Link from 'next/link'
import { DrawerTrigger } from '~/app/asset-risks/_components/drawer'
import { WalletInput } from '~/app/asset-risks/_components/wallet-input'
import { WalletDrawer } from '../wallet-drawer'

export function Navbar() {
  return (
    <>
      <div className="sticky top-0 z-30 h-14 min-w-fit border-b border-[#32326A] text-base lg:h-16">
        <nav className="relative mx-auto box-border flex h-full max-w-[1780px] items-center justify-between px-4 lg:px-8">
          <ul className="flex h-full items-center">
            <li className="mr-4 lg:mr-8">
              <Link
                href="/asset-risks"
                className="font-oswald text-[34px] font-semibold uppercase leading-none tracking-[-0.173px]"
              >
                Insight
              </Link>
            </li>
          </ul>
          <div className="hidden items-center gap-3 md:flex">
            <WalletInput size="sm" className="w-[min(45vw,450px)]" />
          </div>
          <div className="inline-block md:hidden">
            <WalletDrawer>
              <DrawerTrigger className="rounded bg-pink-900 px-6 py-2 text-xs font-bold text-white">
                Scan assets
              </DrawerTrigger>
            </WalletDrawer>
          </div>
        </nav>
      </div>
    </>
  )
}
