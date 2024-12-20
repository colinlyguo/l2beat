'use client'

import { getCoreRowModel, getSortedRowModel } from '@tanstack/react-table'
import { useMemo } from 'react'
import { Card } from '~/app/asset-risks/_components/card'
import { BasicTable } from '~/app/asset-risks/_components/table/basic-table'
import { useTable } from '~/hooks/use-table'
import { type TokenEntry, tokenColumns } from './columns'

export function TokensTable() {
  const data = useMemo<TokenEntry[]>(
    () => [
      {
        symbol: 'USDC',
        logoUrl:
          'https://assets.coingecko.com/coins/images/6319/standard/usdc.png',
        managedBy: 'Circle',
        type: 'IOU',
        underlyingTokens: [],
        value: 50,
        balance: 100,
        chainName: 'Arbitrum',
        chainLogoUrl: '/icons/arbitrum.png',
        criticalWarnings: ['a'],
        warnings: ['b'],
      },
      {
        symbol: 'USDC',
        logoUrl:
          'https://assets.coingecko.com/coins/images/6319/standard/usdc.png',
        managedBy: 'Circle',
        type: 'IOU',
        underlyingTokens: [],
        value: 100,
        balance: 100,
        chainName: 'Optimism',
        chainLogoUrl: '/icons/optimism.png',
        criticalWarnings: ['a'],
        warnings: ['b'],
      },
    ],
    [],
  )
  const table = useTable({
    columns: tokenColumns,
    data,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    initialState: {
      sorting: [{ id: 'value', desc: true }],
    },
  })

  return (
    <Card>
      <div className="mb-3 flex items-center justify-between md:mb-6">
        <h2 className="text-2xl font-bold">Assets</h2>
        {/* <FilterInput filter={filter} setFilter={setFilter} /> */}
      </div>
      <BasicTable table={table} />
    </Card>
  )
}

// 'use client'

// import { type Dispatch, type SetStateAction, useState } from 'react'

// import {
//   SortingArrowDownIcon,
//   SortingArrowUpIcon,
// } from '~/icons/sorting-arrows'
// import { cn } from '~/utils/cn'
// import { Card } from '../../../_components/card'
// import { useReport } from '../report-context'
// import { FilterInput } from './filter-input'
// import { TableRow } from './table-row'
// import {
//   type SingleColumnConfig,
//   type Sorting,
//   columnsConfig,
// } from './utils/columnsConfig'

// type SortingState = {
//   selected: string
//   type: 'asc' | 'desc'
// } & Sorting

// export function TokensTable() {
//   const report = useReport()

//   const [sorting, setSorting] = useState<Partial<SortingState>>({
//     selected: 'VALUE',
//     rule: 'numeric',
//     getOrderValue: ({ balance }) => Number(balance),
//     type: 'desc',
//   })
//   const [filter, setFilter] = useState<string>('')

//   let tokens = report.tokens
//   if (sorting.selected) {
//     tokens = tokens.sort((a, b) => {
//       if (!sorting.getOrderValue) return 0
//       const valueA = sorting.getOrderValue(a, 0)
//       const valueB = sorting.getOrderValue(b, 0)
//       if (sorting.rule === 'numeric') {
//         if (typeof valueA !== 'number' || typeof valueB !== 'number') return 0
//         return sorting.type === 'asc'
//           ? Number(valueA) - Number(valueB)
//           : Number(valueB) - Number(valueA)
//       } else {
//         if (typeof valueA !== 'string' || typeof valueB !== 'string') return 0
//         return sorting.type === 'asc'
//           ? valueA.localeCompare(valueB)
//           : valueB.localeCompare(valueA)
//       }
//     })
//   }

//   if (filter) {
//     tokens = tokens.filter((token) =>
//       token.meta?.name?.toLowerCase().includes(filter.toLowerCase()),
//     )
//   }

//   return (
//     <Card className="overflow-x-auto rounded-none sm:rounded-xl">
//       <div className="flex items-center justify-between">
//         <h2 className="text-2xl font-bold">Assets</h2>
//         <FilterInput filter={filter} setFilter={setFilter} />
//       </div>
//       <div
//         className={cn(
//           'mt-3 overflow-x-auto whitespace-pre pb-3 text-base md:mt-6',
//           '-mx-4 w-[calc(100%_+_32px)] px-4 md:-mx-6 md:w-[calc(100%_+_48px)] md:px-6',
//         )}
//       >
//         <table className="w-full border-collapse text-left">
//           <thead className="border-b border-b-gray-200 dark:border-b-zinc-700">
//             <tr>
//               {columnsConfig.map((column) => (
//                 <TableColumnHeader
//                   key={column.name}
//                   column={column}
//                   sorting={sorting}
//                   setSorting={setSorting}
//                 />
//               ))}
//             </tr>
//           </thead>
//           {tokens.map((token) => (
//             <tbody className="group/body" key={token.token.id.toString()}>
//               <TableRow token={token} />
//             </tbody>
//           ))}
//         </table>
//       </div>
//     </Card>
//   )
// }

// function TableColumnHeader({
//   column,
//   sorting,
//   setSorting,
// }: {
//   column: SingleColumnConfig
//   sorting: Partial<SortingState>
//   setSorting: Dispatch<SetStateAction<Partial<SortingState>>>
// }) {
//   const state = sorting.selected === column.name ? sorting.type : undefined

//   const handleSort = () => {
//     if (column.sorting) {
//       if (sorting.selected === column.name) {
//         setSorting({
//           selected: column.name,
//           type: sorting.type === 'asc' ? 'desc' : 'asc',
//           ...column.sorting,
//         })
//       } else {
//         setSorting({
//           selected: column.name,
//           type: 'asc',
//           ...column.sorting,
//         })
//       }
//     }
//   }

//   return (
//     <th
//       className={cn(
//         'whitespace-pre py-2 pl-2 align-bottom text-sm font-medium uppercase text-gray-500 dark:text-gray-50',
//         'pr-3 md:pr-4',
//         'first:pl-[18px] last:pr-[18px]',
//         column.className,
//       )}
//     >
//       <div
//         className={cn(
//           'group/sorting-arrows flex select-none items-end gap-1.5',
//           column.sorting && 'cursor-pointer',
//         )}
//         data-state={state}
//         onClick={handleSort}
//       >
//         {column.sorting && (
//           <div className="flex translate-y-[-4.5px] flex-col">
//             <SortingArrowUpIcon
//               className={cn(
//                 'mb-0.5 fill-gray-500 transition-all',
//                 'group-data-[state=asc]/sorting-arrows:fill-black dark:group-data-[state=asc]/sorting-arrows:fill-white',
//                 'group-data-[state=desc]/sorting-arrows:group-hover/sorting-arrows:fill-black group-data-[state=desc]/sorting-arrows:group-hover/sorting-arrows:opacity-70 dark:group-data-[state=desc]/sorting-arrows:group-hover/sorting-arrows:fill-white dark:group-data-[state=desc]/sorting-arrows:group-hover/sorting-arrows:opacity-60',
//               )}
//             />
//             <SortingArrowDownIcon
//               className={cn(
//                 'fill-gray-500 transition-all',
//                 'group-data-[state=desc]/sorting-arrows:fill-black dark:group-data-[state=desc]/sorting-arrows:fill-white',
//                 'group-hover/sorting-arrows:fill-black group-data-[state=asc]/sorting-arrows:group-hover/sorting-arrows:opacity-70 dark:group-hover/sorting-arrows:fill-white dark:group-data-[state=asc]/sorting-arrows:group-hover/sorting-arrows:opacity-60',
//               )}
//             />
//           </div>
//         )}
//         <div className={cn('flex flex-row items-end gap-1.5')}>
//           {column.name}
//         </div>
//       </div>
//     </th>
//   )
// }
