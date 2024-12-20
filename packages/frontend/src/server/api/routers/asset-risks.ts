import {
  type Layer2,
  type Layer3,
  type StageConfig,
  layer2s,
  layer3s,
} from '@l2beat/config'
import {
  type TokenBridgeRecord,
  type TokenMetaRecord,
  type TokenRecord,
} from '@l2beat/database'
import { type AssetRisksBalanceRecord } from '@l2beat/database/dist/asset-risks/balance/entity'
import { TRPCError } from '@trpc/server'
import { getAddress } from 'viem'
import { z } from 'zod'
import { db } from '~/server/database'
import { refreshBalancesOfAddress } from '~/server/features/asset-risks/refresh-balances-of-address'
import { refreshTokensOfAddress } from '~/server/features/asset-risks/refresh-tokens-of-address'
import { procedure, router } from '../trpc'

const projectsByChainId = [...layer2s, ...layer3s].reduce<
  Record<number, Layer2 | Layer3>
>((acc, p) => {
  if (p.chainConfig?.chainId) {
    acc[p.chainConfig.chainId] = p
  }
  return acc
}, {})

export const assetRisksRouter = router({
  refreshTokens: procedure
    .input(
      z.object({
        address: z
          .string()
          .regex(/^0x[a-fA-F0-9]{40}$/)
          .transform((arg) => getAddress(arg)),
      }),
    )
    .mutation(async ({ input }) => {
      return await refreshTokensOfAddress(input.address)
    }),

  refreshBalances: procedure
    .input(
      z.object({
        address: z
          .string()
          .regex(/^0x[a-fA-F0-9]{40}$/)
          .transform((arg) => getAddress(arg)),
      }),
    )
    .mutation(async ({ input }) => {
      return await refreshBalancesOfAddress(input.address)
    }),

  report: procedure
    .input(
      z.object({
        address: z
          .string()
          .regex(/^0x[a-fA-F0-9]{40}$/)
          .transform((arg) => getAddress(arg)),
      }),
    )
    .query(async ({ input }) => {
      await db.assetRisksUser.upsert({
        address: input.address,
      })
      const user = await db.assetRisksUser.findUserByAddress(input.address)
      if (!user) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'User not found',
        })
      }
      const networks = await db.network.getAll()
      const externalBridges = await db.externalBridge.getAll()
      const bridges = await db.tokenBridge.getAll()

      const balances = (
        await db.assetRisksBalance.getAllForUser(user.id)
      ).reduce<Record<string, AssetRisksBalanceRecord>>((acc, b) => {
        acc[b.tokenId] = b
        return acc
      }, {})

      const userTokenIds = Object.keys(balances)

      const tokens: Record<string, TokenRecord> = {}
      const relations: Record<string, TokenBridgeRecord> = {}

      let tokensToCheck: string[] = userTokenIds

      while (tokensToCheck.length > 0) {
        const newTokens = await db.token.getByIds(tokensToCheck)
        for (const token of newTokens) {
          tokens[token.id] = token
        }
        const newRelations =
          await db.tokenBridge.getByTargetTokenIds(tokensToCheck)
        tokensToCheck = []
        for (const relation of newRelations) {
          if (relations[relation.id]) continue
          relations[relation.id] = relation
          if (!tokens[relation.sourceTokenId]) {
            tokensToCheck.push(relation.sourceTokenId)
          }
        }
      }

      const tokenMeta = (
        await db.tokenMeta.getByTokenIdsAndSource(
          Object.values(tokens).map((t) => t.id),
          'Aggregate',
        )
      ).reduce<Record<string, TokenMetaRecord>>((acc, meta) => {
        acc[meta.tokenId] = meta
        return acc
      }, {})

      // TODO: Fetch info about prices / etc.

      const chains = networks.reduce<
        Record<
          string,
          {
            name: string
            risks: {
              text: string
              isCritical?: boolean
            }[]
            stage?: StageConfig['stage']
          }
        >
      >((acc, { id, name, chainId }) => {
        const chain = chainId && projectsByChainId[chainId]
        if (chain) {
          acc[id] = {
            name: chain.display.name,
            stage: 'stage' in chain ? chain.stage?.stage : undefined,
            risks: (chain?.technology
              ? [
                  chain.technology.stateCorrectness,
                  chain.technology.newCryptography,
                  chain.technology.dataAvailability,
                  chain.technology.operator,
                  chain.technology.forceTransactions,
                  ...(chain.technology.exitMechanisms ?? []),
                  chain.technology.massExit,
                  ...(chain.technology.otherConsiderations ?? []),
                ].flatMap((choice) => choice?.risks ?? [])
              : []
            ).map((r) => ({
              text: `${r.category} ${r.text}`,
              isCritical: r.isCritical,
            })),
          }
        } else {
          acc[id] = {
            name,
            risks: [],
          }
        }
        return acc
      }, {})

      return {
        usdValue: 0,
        tokensRefreshedAt: user.tokensRefreshedAt,
        balancesRefreshedAt: user.balancesRefreshedAt,
        chains,
        bridges,
        externalBridges,
        relations,
        tokens: Object.values(tokens).map((token) => {
          return {
            token,
            meta: tokenMeta[token.id],
            balance: balances[token.id]?.balance ?? '0',
          }
        }),
      }
    }),
})
