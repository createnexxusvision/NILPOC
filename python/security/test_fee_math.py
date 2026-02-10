from hypothesis import given, strategies as st

BPS = 10_000

@given(amount=st.integers(min_value=1, max_value=10**24), fee_bps=st.integers(min_value=0, max_value=BPS))
def test_fee_split_never_negative(amount: int, fee_bps: int):
    fee = (amount * fee_bps) // BPS
    net = amount - fee
    assert 0 <= fee <= amount
    assert 0 <= net <= amount
    assert fee + net == amount
