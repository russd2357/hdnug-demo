using System.Net.Mail;
using System.Text;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

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

var factory = new ConnectionFactory() { 
    HostName = hostname,
    UserName = username,
    Password = password };

using var connection = await factory.CreateConnectionAsync();
using var channel = await connection.CreateChannelAsync();

await channel.QueueDeclareAsync(queue: queueName, 
    durable: true, 
    exclusive: false, 
    autoDelete: false,
    arguments: null);

await channel.BasicQosAsync(prefetchCount: 1, prefetchSize: 0, global: false);

var consumer = new AsyncEventingBasicConsumer(channel);
consumer.ReceivedAsync += async (model, ea) =>
{
    var body = ea.Body.ToArray();
    var message = Encoding.UTF8.GetString(body);
    Console.WriteLine($" [x] {DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss.fff")} Received {message}");
    await Task.Delay(5000); // Simulate some work
    Console.WriteLine($" [x] {DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss.fff")} Order processed");

    // Acknowledge the message
    await channel.BasicAckAsync(deliveryTag: ea.DeliveryTag, multiple: false);
};

await channel.BasicConsumeAsync(queue: queueName, 
    autoAck: false, // Set to false to enable manual acknowledgment
    consumer: consumer);

// Keep the application running
var tcs = new TaskCompletionSource();
await tcs.Task;