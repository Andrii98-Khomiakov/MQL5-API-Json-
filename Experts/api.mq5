//+------------------------------------------------------------------+
//
// Copyright (C) 2019 Nikolai Khramkov
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//+------------------------------------------------------------------+

// TODO: Comissinos
// TODO: Experation
// TODO: Devitation
// TODO: Add comments
// TODO: Standard O/P reply

#property copyright   "Copyright 2019, Nikolai Khramkov."
#property link        "https://github.com/khramkov"
#property version     "1.00"
#property description "MQL5 JSON API"
#property description "See github link for documentation" 

#include <Trade/AccountInfo.mqh>
#include <Trade/Trade.mqh>
#include <Zmq/Zmq.mqh>
#include <json.mqh>

string HOST="*";
int SYS_PORT=15555;
int DATA_PORT=15556;
int LIVE_PORT=15557;

// ZeroMQ Cnnections
Context context("MQL5 JSON API");
Socket sysSocket(context,ZMQ_REP);
Socket dataSocket(context,ZMQ_PUSH);
Socket liveSocket(context,ZMQ_PUSH);

// Global variables
bool debug = true;
bool liveStram = true;
datetime lastBar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   /* Bindinig ZMQ ports on init */
   
   // OnTimer() function event genegation - 1 millisecond
   EventSetMillisecondTimer(1);
   
   sysSocket.bind(StringFormat("tcp://%s:%d",HOST,SYS_PORT));
   dataSocket.bind(StringFormat("tcp://%s:%d",HOST,DATA_PORT));
   liveSocket.bind(StringFormat("tcp://%s:%d",HOST,LIVE_PORT));
   
   Print("Binding 'System' socket on port "+IntegerToString(SYS_PORT)+"...");
   Print("Binding 'Data' socket on port "+IntegerToString(DATA_PORT)+"...");
   Print("Binding 'Live' socket on port "+IntegerToString(LIVE_PORT)+"...");

   sysSocket.setLinger(1000);

   // Number of messages to buffer in RAM.
   sysSocket.setSendHighWaterMark(1);
   dataSocket.setSendHighWaterMark(1);
   liveSocket.setSendHighWaterMark(1);

   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   /* Unbinding ZMQ ports on denit */
   
   Print(__FUNCTION__," Deinitialization reason code = ",reason); 

   sysSocket.unbind(StringFormat("tcp://%s:%d",HOST,SYS_PORT));
   dataSocket.unbind(StringFormat("tcp://%s:%d",HOST,DATA_PORT));
   liveSocket.unbind(StringFormat("tcp://%s:%d",HOST,LIVE_PORT));
   
   Print("Unbinding 'System' socket on port "+IntegerToString(SYS_PORT)+"..");
   Print("Unbinding 'Data' socket on port "+IntegerToString(DATA_PORT)+"..");
   Print("Unbinding 'Live' socket on port "+IntegerToString(LIVE_PORT)+"..");

  }
  
//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
  
   ZmqMsg request;
   
   // Get request from client via System socket.
   sysSocket.recv(request,true);
   
   // Request recived
   if(request.size()>0)
     { 
      // Pull request to RequestHandler() and get reply.
      string reply = RequestHandler(request);
      // Pull reply to client via System socket.
      InformClientSocket(sysSocket, reply);
     }
   
   
   // If live stream == true, push last candle to liveSocket. 
   if(liveStram)
      {
         datetime thisBar=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE);
         if(lastBar!=thisBar)
           {
            MqlRates rates[1];
            CJAVal candle;
      
            if(CopyRates(_Symbol,_Period,1,1,rates)!=1) { /*error processing */ };
            
            candle[0] = (long) rates[0].time;
            candle[1] = (double) rates[0].open;
            candle[2] = (double) rates[0].high;
            candle[3] = (double) rates[0].low;
            candle[4] = (double) rates[0].close;
            candle[5] = (double) rates[0].tick_volume;
            
            string t=candle.Serialize();
            InformClientSocket(liveSocket,t);
            
            lastBar=thisBar;
           }
      } 
  }
  
//+------------------------------------------------------------------+
//| Request handler                                                  |
//+------------------------------------------------------------------+
string RequestHandler(ZmqMsg &request)
  {
   string reply;
   CJAVal message;
   
   if(TerminalInfoInteger(TERMINAL_CONNECTED))
      {
         ResetLastError();
         // Get data from reguest
         string msg=request.getData();
         
         if(debug==true) {Print("Processing:"+msg);}
         
         // Deserialize msg to CJAVal array
         if(!message.Deserialize(msg))
           {
            ActionDoneOrError(true, GetLastError(), "Deserialization Error", __FUNCTION__);
            Alert("Deserialization Error");
            ExpertRemove();
           }
         
         // Process action command
         string action = message["action"].ToStr();
         if(action=="CONFIG")          {ScriptConfiguration(message);}
         else if(action=="ACCOUNT")    {GetAccountInfo();}
         else if(action=="BALANCE")    {GetBalanceInfo();}
         else if(action=="HISTORY")    {HistoryInfo(message);}
         else if(action=="TRADE")      {TradingModule(message);}
         else if(action=="POSITIONS")  {GetPositions(message);}
         else if(action=="ORDERS")     {GetOrders(message);}
         
         // Action command error processing
         else {ActionDoneOrError(true, GetLastError(), "Wrong action command", __FUNCTION__);} 
         
         reply="OK";
      }
   // If terminal disconnected
   else {reply="TERMINAL DISCONNECTED";}
   
   return(reply);
  }
  
//+------------------------------------------------------------------+
//| Reconfigure the script params                                    |
//+------------------------------------------------------------------+
void ScriptConfiguration(CJAVal &dataObject)
  {  
   ResetLastError();
   string sym=dataObject["symbol"].ToStr();
   ENUM_TIMEFRAMES tf=GetTimeframe(dataObject["chartTF"].ToStr());
   
   if(SymbolInfoInteger(sym, SYMBOL_EXIST)==1)
      {
         ChartSetSymbolPeriod(0, sym, tf);
         ActionDoneOrError(false, GetLastError(), "OK", __FUNCTION__);
      }
   else 
      {
         ActionDoneOrError(true, GetLastError(), "Symbol name dosn't exist", __FUNCTION__);
      }  
  }

//+------------------------------------------------------------------+
//| Account information                                              |
//+------------------------------------------------------------------+
void GetAccountInfo()
  {  
   CJAVal info;
   
   info["broker"] = AccountInfoString(ACCOUNT_COMPANY);
   info["currency"] = AccountInfoString(ACCOUNT_CURRENCY);
   info["server"] = AccountInfoString(ACCOUNT_SERVER); 
   info["trading_allowed"] = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   info["bot_trading"] = AccountInfoInteger(ACCOUNT_TRADE_EXPERT);   
   info["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   info["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   info["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   info["margin_free"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   info["margin_level"] = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   string t=info.Serialize();
   InformClientSocket(dataSocket,t);
  }

//+------------------------------------------------------------------+
//| Balance information                                              |
//+------------------------------------------------------------------+
void GetBalanceInfo()
  {  
      CJAVal info;
         
      info["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
      info["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
      info["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
      info["margin_free"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      
      string t=info.Serialize();
      InformClientSocket(dataSocket,t);
  }
  

//+------------------------------------------------------------------+
//| Get historical data                                              |
//+------------------------------------------------------------------+
void HistoryInfo(CJAVal &dataObject)
  {   
      CJAVal candles;
      MqlRates rates[];
      
      int copied;    
      string actionType=dataObject["actionType"].ToStr();
      string symbol=dataObject["symbol"].ToStr();
      ENUM_TIMEFRAMES period=GetTimeframe(dataObject["chartTF"].ToStr()); 
      datetime fromDate=StringToTime(dataObject["fromDate"].ToStr());

      if(debug==true)
         {
         Print("Fetching HISTORY");
         Print("1) Symbol:"+symbol);
         Print("2) Timeframe:"+EnumToString(period));
         Print("3) Date from:"+TimeToString(fromDate));
         }
      copied=CopyRates(symbol,period,fromDate,TimeCurrent(),rates);
      if(copied)

        {
         for(int i=0;i<copied;i++)
           {
            candles[i].Add(rates[i].time,TIME_DATE|TIME_MINUTES|TIME_SECONDS);
            candles[i].Add(rates[i].open);
            candles[i].Add(rates[i].high);
            candles[i].Add(rates[i].low);
            candles[i].Add(rates[i].close);
            candles[i].Add(rates[i].tick_volume);
           }
         string t=candles.Serialize();
         InformClientSocket(dataSocket,t);
        }
  }

//+------------------------------------------------------------------+
//| Fetch positions information                               |
//+------------------------------------------------------------------+
void GetPositions(CJAVal &dataObject)
  {
      if(debug==true) {Print("Fetching positions...");}
      
      CPositionInfo myposition;
      CJAVal data, position;
   
      // get positions  
      int positionsTotal=PositionsTotal();
      
      if(!positionsTotal) {data["positions"].Add(position);}
      // go through positions in a loop
      for(int i=0;i<positionsTotal;i++)
        {
         ResetLastError();
         
         if (myposition.Select(PositionGetSymbol(i)))
            {
              position["id"] = PositionGetInteger(POSITION_IDENTIFIER);
              position["magic"] = PositionGetInteger(POSITION_MAGIC);
              position["symbol"] = PositionGetString(POSITION_SYMBOL);
              position["type"] = EnumToString(ENUM_POSITION_TYPE(PositionGetInteger(POSITION_TYPE)));
              position["time_setup"]=PositionGetInteger(POSITION_TIME);
              position["open"] = PositionGetDouble(POSITION_PRICE_OPEN);
              position["stoploss"] = PositionGetDouble(POSITION_SL);
              position["takeprofit"] = PositionGetDouble(POSITION_TP);
              position["volume"] = PositionGetDouble(POSITION_VOLUME);
            
              data["positions"].Add(position);
            }    
          else        
            {
              data["error"]= GetLastError();
              PrintFormat("Error when obtaining positions from the list to the cache. Error code: %d",GetLastError());
            }
         }
      string t=data.Serialize();
      InformClientSocket(dataSocket,t);
  }

//+------------------------------------------------------------------+
//| Fetch orders information                               |
//+------------------------------------------------------------------+
void GetOrders(CJAVal &dataObject)
  {

   if(debug==true) {Print("Fetching orders...");}
   
   COrderInfo myorder;
   CJAVal data, order;
   
   if (HistorySelect(0,TimeCurrent()))   // все ордера
      {    
         int ordersTotal = OrdersTotal();
         
         if(!ordersTotal) {data["orders"].Add(order);}
         
         for(int i=0;i<ordersTotal;i++)
          {
            ResetLastError();
            
            if (myorder.Select(OrderGetTicket(i))) 
             {    
               order["id"]= (string) myorder.Ticket();
               order["magic"] = OrderGetInteger(ORDER_MAGIC); 
               order["symbol"] = OrderGetString(ORDER_SYMBOL);
               order["type"] = EnumToString(ENUM_ORDER_TYPE(OrderGetInteger(ORDER_TYPE)));
               order["time_setup"]=OrderGetInteger(ORDER_TIME_SETUP);
               order["open"] = OrderGetDouble(ORDER_PRICE_OPEN);
               order["stoploss"] = OrderGetDouble(ORDER_SL);
               order["takeprofit"] = OrderGetDouble(ORDER_TP);
               order["volume"] = OrderGetDouble(ORDER_VOLUME_INITIAL);
      
               data["orders"].Add(order);
             }    
           else        
             {
               // call OrderGetTicket() was completed unsuccessfully
               data["error"]= GetLastError();
               PrintFormat("Error when obtaining an order from the list to the cache. Error code: %d",GetLastError());
             }
           }
      }
      
    string t=data.Serialize();
    InformClientSocket(dataSocket,t);
  }

//+------------------------------------------------------------------+
//| Trading module                                                   |
//+------------------------------------------------------------------+
void TradingModule(CJAVal &dataObject)
  {
  
   CTrade trade;
   
   string actionType = dataObject["actionType"].ToStr();
   string symbol=dataObject["symbol"].ToStr();
   int idNimber=dataObject["id"].ToInt();
   double volume=dataObject["volume"].ToDbl();
   double SL=dataObject["stoploss"].ToDbl();
   double TP=dataObject["takeprofit"].ToDbl();
   double price=NormalizeDouble(dataObject["price"].ToDbl(),_Digits);
   datetime expiration=TimeTradeServer()+PeriodSeconds(PERIOD_D1);
   double deviation=dataObject["deviation"].ToDbl();  

   if(actionType=="BUY" || actionType=="SELL")
      {  
         ENUM_ORDER_TYPE orderType=ORDER_TYPE_BUY;                      
                             
         if(actionType=="ORDER_TYPE_SELL") {orderType=ORDER_TYPE_SELL;}
         
         if(!trade.PositionOpen(symbol,orderType,price,volume,SL,TP))
            {OrderDoneOrError(true, __FUNCTION__, trade);}
         else 
            {OrderDoneOrError(false, __FUNCTION__, trade);}
        }

   else if(actionType=="BUY_LIMIT" || actionType=="SELL_LIMIT" || actionType=="BUY_STOP" || actionType=="SELL_STOP")
      {  
         if(actionType=="BUY_LIMIT") 
            {
               if(!trade.BuyLimit(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration))
                  {OrderDoneOrError(true, __FUNCTION__, trade);}
               else
                  {OrderDoneOrError(false, __FUNCTION__, trade);}
            }
         else if(actionType=="SELL_LIMIT")
            {
               if(!trade.SellLimit(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration))
                  {OrderDoneOrError(true, __FUNCTION__, trade);}
               else
                  {OrderDoneOrError(false, __FUNCTION__, trade);}
            }
         else if(actionType=="BUY_STOP")
            {
               if(!trade.BuyStop(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration))
                  {OrderDoneOrError(true, __FUNCTION__, trade);}
               else
                  {OrderDoneOrError(false, __FUNCTION__, trade);}
            }
         else if (actionType=="SELL_STOP")
            {
               if(!trade.SellStop(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration))
                  {OrderDoneOrError(true, __FUNCTION__, trade);}
               else
                  {OrderDoneOrError(false, __FUNCTION__, trade);}
            }
       }
   else if(actionType=="POSITION_MODIFY")
      {
         if(!trade.PositionModify(idNimber,SL,TP)) 
            {OrderDoneOrError(true, __FUNCTION__, trade);}
         else 
            {OrderDoneOrError(false, __FUNCTION__, trade);}
      }
      
   else if(actionType=="POSITION_PARTIAL")
      {
         if(!trade.PositionClosePartial(idNimber,volume)) 
            {OrderDoneOrError(true, __FUNCTION__, trade);}
         else 
            {OrderDoneOrError(false, __FUNCTION__, trade);}
      }
          
   else if(actionType=="POSITION_CLOSE")
      {
         if(!trade.PositionClose(idNimber)) 
            {OrderDoneOrError(true, __FUNCTION__, trade);}
         else 
            {OrderDoneOrError(false, __FUNCTION__, trade);}
      }
   
   else if(actionType=="ORDER_MODIFY")
      {  
         if(!trade.OrderModify(idNimber,price,SL,TP,ORDER_TIME_GTC,expiration))
            {OrderDoneOrError(true, __FUNCTION__, trade);}
         else
            {OrderDoneOrError(false, __FUNCTION__, trade);}
     }
     
   else if(actionType=="ORDER_CANCEL")
      {
         if(!trade.OrderDelete(idNimber))
            {OrderDoneOrError(true, __FUNCTION__, trade);}
         else
            {OrderDoneOrError(false, __FUNCTION__, trade);}
      }
   
   else
      {
         CJAVal conformation;
         conformation["error"]=(bool) true;
         conformation["retcode"]=(int) 0;
         conformation["desription"]=(string)"Wrong actionType command";
         
         string t=conformation.Serialize();
         InformClientSocket(dataSocket,t);
      }

  }
  
//+------------------------------------------------------------------+
//| Convetr chart timeframe from string to enum                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframe(string chartTF)
  {
      ENUM_TIMEFRAMES tf=PERIOD_M1;
      
      if(chartTF=="1m")       {tf=PERIOD_M1;}
      else if(chartTF=="5m")  {tf=PERIOD_M5;}
      else if(chartTF=="15m") {tf=PERIOD_M15;}
      else if(chartTF=="30m") {tf=PERIOD_M30;}
      else if(chartTF=="1h")  {tf=PERIOD_H1;}
      else if(chartTF=="2h")  {tf=PERIOD_H2;}
      else if(chartTF=="3h")  {tf=PERIOD_H3;}
      else if(chartTF=="4h")  {tf=PERIOD_H4;}
      else if(chartTF=="6h")  {tf=PERIOD_H6;}
      else if(chartTF=="8h")  {tf=PERIOD_H8;}
      else if(chartTF=="12h") {tf=PERIOD_H12;}
      else if(chartTF=="1d")  {tf=PERIOD_D1;}
      else if(chartTF=="1w")  {tf=PERIOD_W1;}
      else if(chartTF=="1M")  {tf=PERIOD_MN1;}
      else {} //error
      
      return(tf);
  }
  
//+------------------------------------------------------------------+
//| Trade conformation                                               |
//+------------------------------------------------------------------+
void OrderDoneOrError(bool error, string funcName, CTrade &trade)
   {
      CJAVal conf;
      
      conf["error"]=(bool) error;
      conf["retcode"]=(int) trade.ResultRetcode();
      conf["desription"]=(string) trade.ResultRetcodeDescription();
      conf["deal"]=(int) trade.ResultDeal(); 
      conf["order"]=(int) trade.ResultOrder();
      conf["volume"]=(double) trade.ResultVolume();
      conf["price"]=(double) trade.ResultPrice();
      conf["bid"]=(double) trade.ResultBid();
      conf["ask"]=(double) trade.ResultAsk();
      conf["function"]=(string) funcName;
      string t=conf.Serialize();
      InformClientSocket(dataSocket,t);
   }

//+------------------------------------------------------------------+
//| Action conformation                                              |
//+------------------------------------------------------------------+
void ActionDoneOrError(bool error, int lastError, string desc, string funcName)
   {
      CJAVal conf;
      
      conf["error"]=(bool) error;
      conf["lastError"]=(string) lastError;
      conf["description"]=(string) desc;
      conf["function"]=(string) funcName;
      string t=conf.Serialize();
      InformClientSocket(dataSocket,t);
   }

//+------------------------------------------------------------------+
//| Inform Client via socket                                         |
//+------------------------------------------------------------------+
void InformClientSocket(Socket &workingSocket,string replyMessage)
   {
      if(debug==true) {Print(replyMessage);}
      
      ZmqMsg pushReply(replyMessage);
      workingSocket.send(pushReply,true); // true = non-blocking                                   
   }