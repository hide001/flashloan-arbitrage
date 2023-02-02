**Hi! It's a trading bot meant for doing arbitrage trades on a given list of DEXs**<br>
It finds low price for a coin pregiven DEXs compare to other DEXs in the given list. Then finds a considerable high price of that coin on provided DEXs. Checks the profitablity of this oppurtunity accounting for flash loan fee. If the profit is significant enough it carry outs the below execution.<br>

 **Upon finding an arbitrage opportunity on a given set of cions:**
    <ul>
      <li>Takes flash loan from a preset AAVE protocol address</li>
      <li>Buys coin from low price DEX and sells for higher price</li>
      <li>Flash loan fee and capital is transferred back to lending protocol</li>
      <li>Profit is kept in the contract for withdrawal</li>
    </ul><br>

The project is not upto the point where I expect it to be. Contributors are mostly welcomed. I intend to develop this as a library to be quickly inherited by other contracts.
