import { useState, useEffect, useCallback } from 'react'
import { ethers } from 'ethers'
import EscrowAbi from './abis/NILDealEscrow.json'
import VaultAbi  from './abis/TexasNILDeferredVault.json'
import SplitterAbi from './abis/ClipRevenueSplitter.json'
import './App.css'

const ESCROW_ADDR   = import.meta.env.VITE_ESCROW   as string
const VAULT_ADDR    = import.meta.env.VITE_VAULT_NIL as string
const SPLITTER_ADDR = import.meta.env.VITE_SPLITTER  as string
const USDC_ADDR     = import.meta.env.VITE_USDC      as string
const CHAIN_ID      = Number(import.meta.env.VITE_CHAIN_ID ?? 11155111)

const ERC20_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
]

// ---- Status label maps ----
const ESCROW_STATUS: Record<number, string> = {
  0: 'Pending', 1: 'Delivered', 2: 'Completed', 3: 'Disputed', 4: 'Refunded',
}
const VAULT_STATUS: Record<number, string> = {
  0: 'Pending', 1: 'Cancellable', 2: 'Withdrawable', 3: 'Withdrawn', 4: 'Refunded',
}

declare global { interface Window { ethereum?: any } }

// ---- Shared types ----
interface EscrowDeal {
  id: number; athlete: string; sponsor: string; amount: bigint
  deadline: bigint; status: number; deliveredAt: bigint
}
interface VaultDeal {
  id: number; athlete: string; sponsor: string; college: string
  amount: bigint; unlockTime: bigint; enrollmentConfirmed: boolean; status: number
}

type Tab = 'escrow' | 'vault' | 'splitter'

export default function App() {
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null)
  const [signer, setSigner]     = useState<ethers.Signer | null>(null)
  const [address, setAddress]   = useState('')
  const [chainId, setChainId]   = useState(0)
  const [tab, setTab]           = useState<Tab>('escrow')
  const [status, setStatus]     = useState('')

  // ---- Escrow state ----
  const [escrowDeals, setEscrowDeals]   = useState<EscrowDeal[]>([])
  const [eAthlete, setEAthlete]         = useState('')
  const [eAmount, setEAmount]           = useState('0.01')
  const [eDays, setEDays]               = useState('7')

  // ---- Vault state ----
  const [vaultDeals, setVaultDeals]     = useState<VaultDeal[]>([])
  const [vAthlete, setVAthlete]         = useState('')
  const [vCollege, setVCollege]         = useState('')
  const [vAmount, setVAmount]           = useState('0.01')
  const [vDays, setVDays]               = useState('30')

  // ---- Splitter state ----
  const [nextClipId, setNextClipId]     = useState(1)
  const [sW1, setSW1] = useState(''); const [sB1, setSB1] = useState('5000')
  const [sW2, setSW2] = useState(''); const [sB2, setSB2] = useState('5000')
  const [distClipId, setDistClipId]     = useState('1')
  const [distAmount, setDistAmount]     = useState('1000000') // 1 USDC (6 decimals)

  // ---- Wallet ----
  const connectWallet = useCallback(async () => {
    if (!window.ethereum) { setStatus('MetaMask not found.'); return }
    try {
      const p = new ethers.BrowserProvider(window.ethereum)
      await p.send('eth_requestAccounts', [])
      const s = await p.getSigner()
      const net = await p.getNetwork()
      setProvider(p); setSigner(s)
      setAddress(await s.getAddress())
      setChainId(Number(net.chainId))
      setStatus('Connected')
    } catch (e: unknown) {
      setStatus('Error: ' + (e instanceof Error ? e.message : String(e)))
    }
  }, [])

  useEffect(() => {
    if (window.ethereum) {
      window.ethereum.on('accountsChanged', () => connectWallet())
      window.ethereum.on('chainChanged', () => window.location.reload())
    }
  }, [connectWallet])

  // ---- Load helpers ----
  const loadEscrowDeals = useCallback(async () => {
    if (!provider || !ESCROW_ADDR) return
    try {
      const c = new ethers.Contract(ESCROW_ADDR, EscrowAbi, provider)
      const count: bigint = await c.dealsCount()
      const loaded: EscrowDeal[] = []
      for (let i = 0n; i < count && i < 20n; i++) {
        const d = await c.getDeal(i)
        loaded.push({ id: Number(i), athlete: d.athlete, sponsor: d.sponsor,
          amount: d.amount, deadline: d.deadline, status: Number(d.status), deliveredAt: d.deliveredAt })
      }
      setEscrowDeals(loaded)
    } catch (e: unknown) { setStatus('Load error: ' + (e instanceof Error ? e.message : String(e))) }
  }, [provider])

  const loadVaultDeals = useCallback(async () => {
    if (!provider || !VAULT_ADDR) return
    try {
      const c = new ethers.Contract(VAULT_ADDR, VaultAbi, provider)
      const count: bigint = await c.dealsCount()
      const loaded: VaultDeal[] = []
      for (let i = 0n; i < count && i < 20n; i++) {
        const d = await c.getDeal(i)
        loaded.push({ id: Number(i), athlete: d.athlete, sponsor: d.sponsor, college: d.college,
          amount: d.amount, unlockTime: d.unlockTime,
          enrollmentConfirmed: d.enrollmentConfirmed, status: Number(d.status) })
      }
      setVaultDeals(loaded)
    } catch (e: unknown) { setStatus('Load error: ' + (e instanceof Error ? e.message : String(e))) }
  }, [provider])

  const loadNextClipId = useCallback(async () => {
    if (!provider || !SPLITTER_ADDR) return
    try {
      const c = new ethers.Contract(SPLITTER_ADDR, SplitterAbi, provider)
      setNextClipId(Number(await c.nextClipId()))
    } catch { /* ignore */ }
  }, [provider])

  useEffect(() => { loadEscrowDeals(); loadVaultDeals(); loadNextClipId() }, [loadEscrowDeals, loadVaultDeals, loadNextClipId])

  // ---- Escrow actions ----
  const createEscrowDeal = async () => {
    if (!signer || !ESCROW_ADDR) { setStatus('Connect wallet first.'); return }
    if (!ethers.isAddress(eAthlete)) { setStatus('Invalid athlete address.'); return }
    try {
      const c = new ethers.Contract(ESCROW_ADDR, EscrowAbi, signer)
      const amount = ethers.parseEther(eAmount)
      const deadline = BigInt(Math.floor(Date.now() / 1000) + Number(eDays) * 86400)
      const meta = ethers.keccak256(ethers.toUtf8Bytes('nil-deal-' + Date.now()))
      const tx = await c.createDeal(eAthlete, deadline, meta, { value: amount })
      setStatus('Pending... ' + tx.hash.slice(0, 20))
      await tx.wait()
      await loadEscrowDeals()
      setStatus('Escrow deal created!')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const markDelivered = async (id: number) => {
    if (!signer) return
    try {
      const c = new ethers.Contract(ESCROW_ADDR, EscrowAbi, signer)
      const tx = await c.markDelivered(id)
      setStatus('Pending...')
      await tx.wait()
      await loadEscrowDeals()
      setStatus('Deal #' + id + ' marked delivered')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const confirmDelivery = async (id: number) => {
    if (!signer) return
    try {
      const c = new ethers.Contract(ESCROW_ADDR, EscrowAbi, signer)
      const tx = await c.confirmDelivery(id)
      setStatus('Confirming...')
      await tx.wait()
      await loadEscrowDeals()
      setStatus('Deal #' + id + ' confirmed — funds released!')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const raiseDispute = async (id: number) => {
    if (!signer) return
    try {
      const c = new ethers.Contract(ESCROW_ADDR, EscrowAbi, signer)
      const tx = await c.raiseDispute(id)
      setStatus('Pending...')
      await tx.wait()
      await loadEscrowDeals()
      setStatus('Deal #' + id + ' disputed')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  // ---- Vault actions ----
  const createVaultDeal = async () => {
    if (!signer || !VAULT_ADDR) { setStatus('Connect wallet first.'); return }
    if (!ethers.isAddress(vAthlete)) { setStatus('Invalid athlete address.'); return }
    if (!ethers.isAddress(vCollege)) { setStatus('Invalid college address.'); return }
    try {
      const c = new ethers.Contract(VAULT_ADDR, VaultAbi, signer)
      const amount = ethers.parseEther(vAmount)
      const unlockTime = BigInt(Math.floor(Date.now() / 1000) + Number(vDays) * 86400)
      const meta = ethers.keccak256(ethers.toUtf8Bytes('vault-deal-' + Date.now()))
      const tx = await c.createDeal(vAthlete, vCollege, unlockTime, meta, { value: amount })
      setStatus('Pending... ' + tx.hash.slice(0, 20))
      await tx.wait()
      await loadVaultDeals()
      setStatus('Vault deal created!')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const confirmEnrollment = async (id: number) => {
    if (!signer) return
    try {
      const c = new ethers.Contract(VAULT_ADDR, VaultAbi, signer)
      const tx = await c.confirmEnrollment(id)
      setStatus('Confirming enrollment...')
      await tx.wait()
      await loadVaultDeals()
      setStatus('Deal #' + id + ' enrollment confirmed')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const withdrawVault = async (id: number) => {
    if (!signer) return
    try {
      const c = new ethers.Contract(VAULT_ADDR, VaultAbi, signer)
      const tx = await c.withdraw(id)
      setStatus('Withdrawing...')
      await tx.wait()
      await loadVaultDeals()
      setStatus('Deal #' + id + ' withdrawn!')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  // ---- Splitter actions ----
  const createClip = async () => {
    if (!signer || !SPLITTER_ADDR) { setStatus('Connect wallet first.'); return }
    if (!ethers.isAddress(sW1) || !ethers.isAddress(sW2)) { setStatus('Invalid contributor addresses.'); return }
    const b1 = Number(sB1); const b2 = Number(sB2)
    if (b1 + b2 !== 10000) { setStatus('Basis points must sum to 10000.'); return }
    try {
      const c = new ethers.Contract(SPLITTER_ADDR, SplitterAbi, signer)
      const tx = await c.createClip([sW1, sW2], [b1, b2])
      setStatus('Creating clip...')
      await tx.wait()
      await loadNextClipId()
      setStatus('Clip created! ID=' + (nextClipId))
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const distributeRevenue = async () => {
    if (!signer || !SPLITTER_ADDR || !USDC_ADDR) { setStatus('Connect wallet first.'); return }
    try {
      const usdc = new ethers.Contract(USDC_ADDR, ERC20_ABI, signer)
      const amount = BigInt(distAmount)
      setStatus('Approving USDC...')
      const appTx = await usdc.approve(SPLITTER_ADDR, amount)
      await appTx.wait()
      const c = new ethers.Contract(SPLITTER_ADDR, SplitterAbi, signer)
      const tx = await c.distributeForClip(Number(distClipId), amount)
      setStatus('Distributing...')
      await tx.wait()
      setStatus('Revenue distributed for clip #' + distClipId + '!')
    } catch (e: unknown) { setStatus('Error: ' + (e instanceof Error ? e.message : String(e))) }
  }

  const wrongChain = !!address && chainId !== CHAIN_ID
  const fmt = (addr: string) => addr.slice(0, 6) + '...' + addr.slice(-4)
  const fmtEth = (v: bigint) => ethers.formatEther(v)
  const fmtDate = (ts: bigint) => ts === 0n ? '-' : new Date(Number(ts) * 1000).toLocaleDateString()

  return (
    <div className="nil-app">
      <header>
        <h1>NILPOC Demo</h1>
        <p className="subtitle">Name, Image &amp; Likeness — on-chain</p>
        {address
          ? <div className="badge connected">{fmt(address)}{wrongChain && <span className="warn"> Wrong network</span>}</div>
          : <button className="btn-primary" onClick={connectWallet}>Connect Wallet</button>
        }
      </header>

      {status && <div className="status-bar">{status}</div>}

      <nav className="tabs">
        <button className={tab === 'escrow'   ? 'tab active' : 'tab'} onClick={() => setTab('escrow')}>
          Escrow Deals
        </button>
        <button className={tab === 'vault'    ? 'tab active' : 'tab'} onClick={() => setTab('vault')}>
          Deferred Vault
        </button>
        <button className={tab === 'splitter' ? 'tab active' : 'tab'} onClick={() => setTab('splitter')}>
          Clip Splitter
        </button>
      </nav>

      {/* ===== ESCROW TAB ===== */}
      {tab === 'escrow' && (
        <>
          <div className="grid">
            <section className="card">
              <h2>Create Escrow Deal</h2>
              <p className="card-desc">Sponsor locks ETH; released when delivery is confirmed.</p>
              <label>Athlete address<input value={eAthlete} onChange={e => setEAthlete(e.target.value)} placeholder="0x..." /></label>
              <label>Amount (ETH)<input type="number" step="0.001" value={eAmount} onChange={e => setEAmount(e.target.value)} /></label>
              <label>Deadline (days from now)<input type="number" value={eDays} onChange={e => setEDays(e.target.value)} /></label>
              <button className="btn-primary" onClick={createEscrowDeal} disabled={!signer}>Create Deal</button>
            </section>
            <section className="card">
              <h2>How it works</h2>
              <ol className="how-list">
                <li>Sponsor calls <strong>Create Deal</strong> — ETH locked in contract.</li>
                <li>Athlete posts content, then calls <strong>Mark Delivered</strong>.</li>
                <li>Sponsor calls <strong>Confirm</strong> — ETH released to athlete.</li>
                <li>If sponsor ghosts past deadline, athlete can <strong>Force Release</strong>.</li>
                <li>Either party can <strong>Dispute</strong>; owner arbitrates.</li>
              </ol>
            </section>
          </div>
          <section className="card deals-card">
            <div className="deals-header">
              <h2>On-chain Escrow Deals</h2>
              <button className="btn-secondary" onClick={loadEscrowDeals} disabled={!provider}>Refresh</button>
            </div>
            {escrowDeals.length === 0
              ? <p className="empty">No escrow deals yet.</p>
              : (
                <table>
                  <thead><tr>
                    <th>#</th><th>Sponsor</th><th>Athlete</th>
                    <th>ETH</th><th>Deadline</th><th>Status</th><th>Actions</th>
                  </tr></thead>
                  <tbody>
                    {escrowDeals.map(d => (
                      <tr key={d.id}>
                        <td>{d.id}</td>
                        <td className="addr">{fmt(d.sponsor)}</td>
                        <td className="addr">{fmt(d.athlete)}</td>
                        <td>{fmtEth(d.amount)}</td>
                        <td>{fmtDate(d.deadline)}</td>
                        <td><span className={'badge s' + d.status}>{ESCROW_STATUS[d.status]}</span></td>
                        <td className="action-cell">
                          {d.status === 0 && <button className="btn-sm" onClick={() => markDelivered(d.id)}>Mark Delivered</button>}
                          {d.status === 1 && <button className="btn-sm btn-green" onClick={() => confirmDelivery(d.id)}>Confirm</button>}
                          {(d.status === 0 || d.status === 1) && <button className="btn-sm btn-red" onClick={() => raiseDispute(d.id)}>Dispute</button>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )
            }
          </section>
        </>
      )}

      {/* ===== VAULT TAB ===== */}
      {tab === 'vault' && (
        <>
          <div className="grid">
            <section className="card">
              <h2>Create Vault Deal</h2>
              <p className="card-desc">Lock ETH for athlete until enrollment is confirmed and unlock time passes.</p>
              <label>Athlete address<input value={vAthlete} onChange={e => setVAthlete(e.target.value)} placeholder="0x..." /></label>
              <label>College address<input value={vCollege} onChange={e => setVCollege(e.target.value)} placeholder="0x..." /></label>
              <label>Amount (ETH)<input type="number" step="0.001" value={vAmount} onChange={e => setVAmount(e.target.value)} /></label>
              <label>Unlock (days from now)<input type="number" value={vDays} onChange={e => setVDays(e.target.value)} /></label>
              <button className="btn-primary" onClick={createVaultDeal} disabled={!signer}>Create Vault Deal</button>
            </section>
            <section className="card">
              <h2>How it works</h2>
              <ol className="how-list">
                <li>Verifier (school/brand) calls <strong>Create</strong> — ETH vaulted.</li>
                <li>Verifier calls <strong>Confirm Enrollment</strong> when athlete signs.</li>
                <li>After unlock time, athlete calls <strong>Withdraw</strong>.</li>
                <li>If enrollment falls through, verifier can <strong>Refund</strong>.</li>
              </ol>
            </section>
          </div>
          <section className="card deals-card">
            <div className="deals-header">
              <h2>On-chain Vault Deals</h2>
              <button className="btn-secondary" onClick={loadVaultDeals} disabled={!provider}>Refresh</button>
            </div>
            {vaultDeals.length === 0
              ? <p className="empty">No vault deals yet.</p>
              : (
                <table>
                  <thead><tr>
                    <th>#</th><th>Sponsor</th><th>Athlete</th><th>College</th>
                    <th>ETH</th><th>Unlock</th><th>Enrolled</th><th>Status</th><th>Actions</th>
                  </tr></thead>
                  <tbody>
                    {vaultDeals.map(d => (
                      <tr key={d.id}>
                        <td>{d.id}</td>
                        <td className="addr">{fmt(d.sponsor)}</td>
                        <td className="addr">{fmt(d.athlete)}</td>
                        <td className="addr">{fmt(d.college)}</td>
                        <td>{fmtEth(d.amount)}</td>
                        <td>{fmtDate(d.unlockTime)}</td>
                        <td>{d.enrollmentConfirmed ? 'Yes' : 'No'}</td>
                        <td><span className={'badge s' + d.status}>{VAULT_STATUS[d.status]}</span></td>
                        <td className="action-cell">
                          {d.status === 0 && !d.enrollmentConfirmed && (
                            <button className="btn-sm btn-green" onClick={() => confirmEnrollment(d.id)}>Confirm Enroll</button>
                          )}
                          {d.status === 2 && (
                            <button className="btn-sm btn-green" onClick={() => withdrawVault(d.id)}>Withdraw</button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )
            }
          </section>
        </>
      )}

      {/* ===== SPLITTER TAB ===== */}
      {tab === 'splitter' && (
        <>
          <div className="grid">
            <section className="card">
              <h2>Register Clip</h2>
              <p className="card-desc">Owner registers a clip with two contributors and their revenue splits (basis points, must sum to 10000).</p>
              <label>Contributor 1 address<input value={sW1} onChange={e => setSW1(e.target.value)} placeholder="0x..." /></label>
              <label>Contributor 1 BPS (e.g. 7000 = 70%)<input type="number" value={sB1} onChange={e => setSB1(e.target.value)} /></label>
              <label>Contributor 2 address<input value={sW2} onChange={e => setSW2(e.target.value)} placeholder="0x..." /></label>
              <label>Contributor 2 BPS<input type="number" value={sB2} onChange={e => setSB2(e.target.value)} /></label>
              <button className="btn-primary" onClick={createClip} disabled={!signer}>Register Clip</button>
            </section>
            <section className="card">
              <h2>Distribute USDC Revenue</h2>
              <p className="card-desc">Anyone can distribute USDC to a clip's contributors. You must approve USDC first (done automatically).</p>
              <label>Clip ID<input type="number" value={distClipId} onChange={e => setDistClipId(e.target.value)} /></label>
              <label>Amount (USDC smallest unit, 6 decimals — e.g. 1000000 = 1 USDC)
                <input type="number" value={distAmount} onChange={e => setDistAmount(e.target.value)} />
              </label>
              <button className="btn-primary" onClick={distributeRevenue} disabled={!signer}>Approve &amp; Distribute</button>
              <p className="card-desc" style={{marginTop: '0.6rem'}}>Next clip ID: <strong>{nextClipId}</strong></p>
            </section>
          </div>
          <section className="card">
            <h2>How it works</h2>
            <ol className="how-list">
              <li>Owner calls <strong>Register Clip</strong> with contributor wallets + basis-point splits.</li>
              <li>A sponsor or platform calls <strong>Approve &amp; Distribute</strong> with a USDC amount.</li>
              <li>Contract pulls USDC from caller and instantly forwards each contributor's share.</li>
              <li>No balances stored — everything forwarded in one tx.</li>
            </ol>
          </section>
        </>
      )}

      <footer>
        <p>
          Escrow: <code>{ESCROW_ADDR || 'not configured'}</code>
          {' | '}
          Vault: <code>{VAULT_ADDR || 'not configured'}</code>
          {' | '}
          Splitter: <code>{SPLITTER_ADDR || 'not configured'}</code>
        </p>
      </footer>
    </div>
  )
}
