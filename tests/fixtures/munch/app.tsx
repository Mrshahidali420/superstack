interface Props { title: string; }
export const Card = (props: Props) => <div>{props.title}</div>;
function App() { return <Card title="x" />; }
