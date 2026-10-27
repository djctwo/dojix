//+------------------------------------------------------------------+
//| DojixPriceFeed.mq5                                               |
//| Writes live bid/ask prices to Common Files for Dojix to read.    |
//| Attach to any chart — updates every 1 second.                    |
//| No personal data is written — only public market prices.         |
//+------------------------------------------------------------------+
#property copyright "Copyright (C) 2026 Douglas Cleary. GPL-3.0-or-later."
#property version   "1.00"
#property strict

input string Symbols = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD"; // Comma-separated symbols (use your broker's names)
input int    UpdateSeconds = 1; // Update interval in seconds

string symbolList[];

//+------------------------------------------------------------------+
int OnInit()
{
   int count = StringSplit(Symbols, ',', symbolList);
   if(count == 0)
   {
      Print("DojixPriceFeed: No symbols configured");
      return INIT_FAILED;
   }

   // Trim whitespace from symbol names
   for(int i = 0; i < count; i++)
      StringTrimLeft(symbolList[i]);

   EventSetTimer(UpdateSeconds);
   Print("DojixPriceFeed: Watching ", count, " symbols, updating every ", UpdateSeconds, "s");

   // Write immediately on attach
   WritePrices();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("DojixPriceFeed: Stopped");
}

//+------------------------------------------------------------------+
void OnTimer()
{
   WritePrices();
}

//+------------------------------------------------------------------+
void WritePrices()
{
   int handle = FileOpen("DojixPrices.json", FILE_WRITE | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("DojixPriceFeed: Failed to open file");
      return;
   }

   string json = "{\"ts\":\"" + TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS) + "\",\"prices\":[";

   int written = 0;
   for(int i = 0; i < ArraySize(symbolList); i++)
   {
      string sym = symbolList[i];
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

      // Skip if symbol not available
      if(bid == 0 && ask == 0)
         continue;

      if(written > 0)
         json += ",";

      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      json += "{\"s\":\"" + sym + "\""
            + ",\"b\":" + DoubleToString(bid, digits)
            + ",\"a\":" + DoubleToString(ask, digits)
            + "}";
      written++;
   }

   json += "]}";
   FileWriteString(handle, json);
   FileClose(handle);
}
//+------------------------------------------------------------------+
