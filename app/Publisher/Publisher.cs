using System.Text;
using RabbitMQ.Client;
using Publisher;

var hostname = Environment.GetEnvironmentVariable("RABBITMQ_HOSTNAME");
if (string.IsNullOrEmpty(hostname))
{
    Console.WriteLine("RABBITMQ_HOSTNAME environment variable is not set.");
    return;
}

var username = Environment.GetEnvironmentVariable("RABBITMQ_USERNAME");
if (string.IsNullOrEmpty(username))
{
    Console.WriteLine("RABBITMQ_USERNAME environment variable is not set.");
    return;
}

var password = Environment.GetEnvironmentVariable("RABBITMQ_PASSWORD");
if (string.IsNullOrEmpty(password))
{
    Console.WriteLine("RABBITMQ_PASSWORD environment variable is not set.");
    return;
}

const string queueName = "orders-task";

try
{
    var factory = new ConnectionFactory() { 
        HostName = hostname,
        Port = 5672,
        UserName = username,
        Password = password};

    using var connection = await factory.CreateConnectionAsync();
    using var channel = await connection.CreateChannelAsync();

    await channel.QueueDeclareAsync(queue: queueName, 
        durable: true, 
        exclusive: false, 
        autoDelete: false,
        arguments: null);

    // For our demo, the publisher will send 50 messages to the queue at 2 second intervals.

    for (int i = 0; i < 200; i++)
    {
        var message = OrderUtils.CreateOrder();
        var body = Encoding.UTF8.GetBytes(message);

        var properties = new BasicProperties {
            Persistent = true
        };

        await channel.BasicPublishAsync(exchange: string.Empty, 
            routingKey: queueName, 
            basicProperties: properties,
            mandatory: true,
            body: body);

            
        Console.WriteLine($" [x] Sent {message}");
        await Task.Delay(750);
    }
}
catch (Exception ex)
{
    Console.WriteLine($"Error: {ex.Message}");
}

Console.WriteLine(" Press [enter] to exit.");
Console.ReadLine();

