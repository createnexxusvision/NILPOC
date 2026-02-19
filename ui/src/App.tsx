import { useState, useEffect, useCallback } from 'react'
import { ethers } from 'ethers'
import DealEngineAbi from './abis/DealEngine.json'
import PayoutRouterAbi from './abis/PayoutRouter.json'
import './App.css'

const DEAL_ENGINE_ADDR = import.meta.env.VITE_DEAL_ENGINE as string
const ROUTER_ADDR      = import.meta.env.VITE_ROUTER      as string
const CHAIN_ID         = Number(import.meta.env.VITE_CHAIN_ID ?? 31337)
const NATIVE           = ethers.ZeroAddress

interface Deal {
  id: string; sponsor: string; athlete: string; token: string
  amount: string; deadline: string; status: number
}
const STATUS_LABELS: Record<number, string> = {
  0: 'Open', 1: 'Delivered', 2: 'Settled',
  3: 'Disputed', 4: 'Refunded', 5: 'ForceSettled',
}

// Extend the window type for MetaMask
declare global {
  interface Window {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ethereum?: any
  }
}

export default function App() {
  const [provider, setProvider]         = useState<ethers.BrowserProvider | null>(null)
  const [signer, setSigner]             = useState<ethers.Signer | null>(null)
  const [address, setAddress]           = useState<string>('')
  const [chainId, setChainId]           = useState<number>(0)
  const [deals, setDeals]               = useState<Deal[]>([])
  const [txStatus, setTxStatus]         = useState<string>('')
  const [athlete, setAthlete]           = useState<string>('')
  const [amountEth, setAmountEth]       = useState<string>('0.01')
  const [days, setDays]                 = useState<string>('7')
  const [rec1, setRec1]                 = useState<string>('')
  const [rec2, setRec2]                 = useState<string>('')
  const [splitAmt, setSplitAmt]         = useState<string>('0.005')

  const connectWallet = useCallback(async () => {
    if (!window.ethereum) { setTxStatus('MetaMask not found.'); return }
    try {
      const p = new ethers.BrowserProvider(window.ethereum)
      await p.send('eth_requestAccounts', [])
      const s = await p.getSigner()
      const net = await p.getNetwork()
      setProvider(p); setSigner(s)
      setAddress(await s.getAddress())
      setChainId(Number(net.chainId))
      setTxStatus('Connected')
    } catch (e: unknown) {
      setTxStatus('Error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }, [])

  useEffect(() => {
    if (window.ethereum) {
      window.ethereum.on('accountsChanged', () => connectWallet())
      window.ethereum.on('chainChanged', () => window.location.reload())
    }
  }, [connectWallet])

  const loadDeals = useCallback(async () => {
    if (!provider || !DEAL_ENGINE_ADDR) return
    try {
      const engine = new ethers.Contract(DEAL_ENGINE_ADDR, DealEngineAbi, provider)
      const count: bigint = await engine.dealCount()
      const loaded: Deal[] = []
      for (let i = 0n; i < count && i < 20n; i++) {
        const d = await engine.getDeal(i)
        loaded.push({
          id: i.toString(), sponsor: d.sponsor, athlete: d.athlete,
          token: d.token, amount: ethers.formatEther(d.amount),
          deadline: new Date(Number(d.deadline) * 1000).toLocaleString(),
          status: Number(d.status),
        })
      }
      setDeals(loaded)
    } catch (e: unknown) {
      setTxStatus('Load error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }, [provider])

  useEffect(() => { loadDeals() }, [loadDeals])

  const createDeal = async () => {
    if (!signer || !DEAL_ENGINE_ADDR) { setTxStatus('Connect wallet first.'); return }
    if (!ethers.isAddress(athlete)) { setTxStatus('Invalid athlete address.'); return }
    try {
      const engine = new ethers.Contract(DEAL_ENGINE_ADDR, DealEngineAbi, signer)
      const amount = ethers.parseEther(amountEth)
      const deadline = BigInt(Math.floor(Date.now() / 1000) + Number(days) * 86400)
      const terms = ethers.keccak256(ethers.toUtf8Bytes('demo-' + Date.now()))
      const tx = await engine.createDeal(athlete, NATIVE, amount, deadline, terms, { value: amount })
      setTxStatus('Tx: ' + tx.hash)
      await tx.wait()
      await loadDeals()
      setTxStatus('Deal created!')
    } catch (e: unknown) {
      setTxStatus('Error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  const markDelivered = async (id: string) => {
    if (!signer) return
    try {
      const engine = new ethers.Contract(DEAL_ENGINE_ADDR, DealEngineAbi, signer)
      const evidence = ethers.keccak256(ethers.toUtf8Bytes('evidence-' + id))
      const tx = await engine.markDelivered(BigInt(id), evidence)
      setTxStatus('Pending...')
      await tx.wait()
      await loadDeals()
      setTxStatus('Deal ' + id + ' marked delivered')
    } catch (e: unknown) {
      setTxStatus('Error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  const approveSettle = async (id: string) => {
    if (!signer) return
    try {
      const engine = new ethers.Contract(DEAL_ENGINE_ADDR, DealEngineAbi, signer)
      const tx = await engine.approveAndSettle(BigInt(id))
      setTxStatus('Settling...')
      await tx.wait()
      await loadDeals()
      setTxStatus('Deal ' + id + ' settled!')
    } catch (e: unknown) {
      setTxStatus('Error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  const doPayout = async () => {
    if (!signer || !ROUTER_ADDR) { setTxStatus('Connect wallet first.'); return }
    if (!ethers.isAddress(rec1) || !ethers.isAddress(rec2)) {
      setTxStatus('Invalid recipient addresses.'); return
    }
    if ([rec1, rec2].some(a => a.toLowerCase() === ROUTER_ADDR.toLowerCase())) {
      setTxStatus('Router address cannot be a recipient.'); return
    }
    try {
      const router = new ethers.Contract(ROUTER_ADDR, PayoutRouterAbi, signer)
      const recipients = [{ recipient: rec1, bps: 5000 }, { recipient: rec2, bps: 5000 }]
      const defTx = await router.defineSplit(recipients)
      setTxStatus('Defining split...')
      await defTx.wait()
      const splitId = (await router.splitCount()) - 1n
      const amount = ethers.parseEther(splitAmt)
      const ref = ethers.keccak256(ethers.toUtf8Bytes('pay-' + Date.now()))
      const payTx = await router.payout(ref, NATIVE, amount, splitId, { value: amount })
      setTxStatus('Paying...')
      await payTx.wait()
      setTxStatus('Split done! splitId=' + splitId)
    } catch (e: unknown) {
      setTxStatus('Error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  const wrongChain = !!address && chainId !== CHAIN_ID

  return (
    <div className="nil-app">
      <header>
        <h1>NILPOC Demo</h1>
        <p className="subtitle">Name, Image &amp; Likeness Protocol on-chain</p>
        {address
          ? (
            <div className="badge connected">
              {address.slice(0, 6)}...{address.slice(-4)}
              {wrongChain && <span className="warn"> Wrong network (need chainId {CHAIN_ID})</span>}
            </div>
          )
          : <button className="btn-primary" onClick={connectWallet}>Connect Wallet</button>
        }
      </header>

      {txStatus && <div className="status-bar">{txStatus}</div>}

      <div className="grid">
        <section className="card">
          <h2>Create ETH Deal</h2>
          <label>
            Athlete address
            <input value={athlete} onChange={e => setAthlete(e.target.value)} placeholder="0x..." />
          </label>
          <label>
            Amount (ETH)
            <input type="number" step="0.001" value={amountEth}
              onChange={e => setAmountEth(e.target.value)} />
          </label>
          <label>
            Deadline (days from now)
            <input type="number" value={days} onChange={e => setDays(e.target.value)} />
          </label>
          <button className="btn-primary" onClick={createDeal} disabled={!signer}>
            Create Deal
          </button>
        </section>

        <section className="card">
          <h2>50/50 ETH Split Payout</h2>
          <label>
            Recipient 1
            <input value={rec1} onChange={e => setRec1(e.target.value)} placeholder="0x..." />
          </label>
          <label>
            Recipient 2
            <input value={rec2} onChange={e => setRec2(e.target.value)} placeholder="0x..." />
          </label>
          <label>
            Total ETH
            <input type="number" step="0.001" value={splitAmt}
              onChange={e => setSplitAmt(e.target.value)} />
          </label>
          <button className="btn-primary" onClick={doPayout} disabled={!signer}>
            Execute Split
          </button>
        </section>
      </div>

      <section className="card deals-card">
        <div className="deals-header">
          <h2>On-chain Deals</h2>
          <button className="btn-secondary" onClick={loadDeals} disabled={!provider}>
            Refresh
          </button>
        </div>
        {deals.length === 0
          ? <p className="empty">No deals on-chain yet.</p>
          : (
            <table>
              <thead>
                <tr>
                  <th>#</th><th>Sponsor</th><th>Athlete</th>
                  <th>Amount</th><th>Deadline</th><th>Status</th><th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {deals.map(d => (
                  <tr key={d.id}>
                    <td>{d.id}</td>
                    <td className="addr">{d.sponsor.slice(0, 8)}...</td>
                    <td className="addr">{d.athlete.slice(0, 8)}...</td>
                    <td>{d.amount} {d.token === NATIVE ? 'ETH' : 'TOKEN'}</td>
                    <td>{d.deadline}</td>
                    <td>
                      <span className={'badge s' + d.status}>
                        {STATUS_LABELS[d.status] ?? String(d.status)}
                      </span>
                    </td>
                    <td>
                      {d.status === 0 && (
                        <button className="btn-sm" onClick={() => markDelivered(d.id)}>
                          Mark Delivered
                        </button>
                      )}
                      {d.status === 1 && (
                        <button className="btn-sm btn-green" onClick={() => approveSettle(d.id)}>
                          Approve &amp; Settle
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        }
      </section>

      <footer>
        <p>
          DealEngine: <code>{DEAL_ENGINE_ADDR || 'not configured'}</code>
          {' | '}
          Router: <code>{ROUTER_ADDR || 'not configured'}</code>
        </p>
      </footer>
    </div>
  )
}
