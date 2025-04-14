
using System;
using System.Text.Json;
using System.Text.Json.Nodes;


namespace Publisher
{
    public class OrderUtils
    {
        public static string CreateOrder()
        {
            Random random = new Random();
            var order = new JsonObject
            {
                ["customerId"] = random.Next(1000, 999999999).ToString("D9")
            }; 

            var items = new JsonArray();
            var numitems = random.Next(1, 10);
            for (int i = 0; i < numitems; i++)
            {
                items.Add(new JsonObject(){
                    ["productId"] = random.Next(1, 999999).ToString("D6"),
                    ["quantity"] = random.Next(1, 10).ToString("D2"),
                    ["price"] = (random.Next(1, 1000) / 100.0).ToString("F2")
                });
            }
            order["items"] = items;
            order["orderDate"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
            
            return JsonSerializer.Serialize(order);
        }
    }
}